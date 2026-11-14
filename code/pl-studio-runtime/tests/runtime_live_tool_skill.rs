#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtom, ChatBatch, ChatPlacement, ChatScope, CompletedEntry, ContentRange, ContentRef,
    PayloadData, ReadDemand, SkillActivationCause, ThreadSkillItem, ThreadWorkspaceMode, TurnState,
    studio::StopThreadRequest,
};
use pl_provider_fixture::{Protocol, ReplyStage, Step};
use pl_studio_runtime::{ConversationEvent, ConversationFeed, ConversationReader};
use serde_json::Value;
use std::{collections::BTreeMap, time::Duration};
use support::{Environment, held_reply, program_reply, prompt_step, reached};

const PROMPT: &str = "read a skill, then hold the next model response";
const CALL: &str = "live-skill-load-call";
const SKILL: &str = "canvas-design";
const DEADLINE: Duration = Duration::from_secs(20);

fn demand() -> ReadDemand {
    ReadDemand {
        max_items: 4,
        max_bytes: 64 * 1024,
    }
}

async fn chat(feed: &mut ConversationFeed) -> Result<ChatBatch> {
    tokio::time::timeout(DEADLINE, async {
        loop {
            match feed.recv().await?.context("feed ended before Chat")? {
                ConversationEvent::Chat { batch } => return Ok(*batch),
                ConversationEvent::Activity { .. } => {}
            }
        }
    })
    .await
    .context("public Chat did not arrive")?
}

fn atoms(entries: Vec<CompletedEntry>) -> Vec<ChatAtom> {
    entries.into_iter().map(|entry| entry.atom).collect()
}

async fn frozen_payload(reader: &ConversationReader, message: &ChatAtom) -> Result<Value> {
    let bytes = match message.payload.as_ref().context("completed payload")? {
        PayloadData::Inline { bytes } => bytes.clone(),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => read_sealed(reader, reference, *byte_length).await?,
    };
    let payload: Value = serde_json::from_slice(&bytes)?;
    ensure!(payload["contract"] == "anywork.chat/1");
    Ok(payload)
}

async fn read_sealed(
    reader: &ConversationReader,
    reference: &ContentRef,
    length: u64,
) -> Result<Vec<u8>> {
    // A deliberately small range forces full-result verification across actual windows, even for
    // a short built-in skill. Do not reconstruct a public result from a checkpoint or a receipt.
    ensure!(
        length <= 1024 * 1024,
        "fixture body exceeded its explicit bound"
    );
    let mut bytes = Vec::new();
    let mut generation = None;
    while (bytes.len() as u64) < length {
        let offset = bytes.len() as u64;
        let window = reader
            .read_content(
                reference,
                ContentRange {
                    offset,
                    max_bytes: (length - offset).min(1024) as u32,
                },
            )
            .await?;
        ensure!(window.offset == offset && window.sealed && window.available_through == length);
        ensure!(!window.bytes.is_empty() && window.bytes.len() <= 1024);
        ensure!(
            generation
                .as_ref()
                .is_none_or(|value| value == &window.generation)
        );
        generation = Some(window.generation);
        bytes.extend(window.bytes);
        ensure!(bytes.len() as u64 <= length);
    }
    Ok(bytes)
}

async fn original_members(feed: &mut ConversationFeed) -> Result<BTreeMap<String, Value>> {
    let first = chat(feed).await?;
    ensure!(first.placement == ChatPlacement::Set && first.from_seq.is_none());
    let mut messages = atoms(first.entries);
    let mut before = first.before;
    for _ in 0..8 {
        let Some(cursor) = before else {
            let mut result = BTreeMap::new();
            for message in messages {
                let payload = frozen_payload(feed.reader(), &message).await?;
                ensure!(
                    result.insert(message.id, payload).is_none(),
                    "duplicate member"
                );
            }
            return Ok(result);
        };
        let page = feed.reader().load_older(&cursor, demand()).await?;
        ensure!(page.placement == ChatPlacement::Prepend && page.from_seq.is_none());
        ensure!(
            page.before.as_ref() != Some(&cursor),
            "cursor did not advance"
        );
        before = page.before;
        messages.splice(0..0, atoms(page.entries));
    }
    anyhow::bail!("fixture exceeded its explicit Children paging bound")
}

async fn live_members(feed: &mut ConversationFeed) -> Result<BTreeMap<String, Value>> {
    let mut members = original_members(feed).await?;
    // The provider receiving a tool result is not the Studio publication barrier. Start from the
    // captured Set and consume the original feed's ordered Appends while the next model is held.
    let arrived = tokio::time::timeout(DEADLINE, async {
        while !members.values().any(|payload| {
            payload["type"] == "tool"
                && payload["data"]["invocation"]["callId"]
                    .as_str()
                    .is_some_and(|id| id.starts_with(&format!("{CALL}:nested:")))
        }) || !members.values().any(|payload| payload["type"] == "skill")
        {
            let append = chat(feed).await?;
            ensure!(append.placement == ChatPlacement::Append && append.from_seq.is_some());
            for message in atoms(append.entries) {
                let payload = frozen_payload(feed.reader(), &message).await?;
                ensure!(
                    members.insert(message.id, payload).is_none(),
                    "Append repeated a completed member"
                );
            }
            ensure!(members.len() <= 32, "fixture exceeded its member bound");
        }
        Ok::<_, anyhow::Error>(())
    })
    .await;
    let identities = members
        .values()
        .map(|payload| (&payload["type"], &payload["data"]["invocation"]["callId"]))
        .collect::<Vec<_>>();
    arrived.with_context(|| format!("held Turn members did not arrive: {identities:?}"))??;
    Ok(members)
}

async fn close_feed(feed: &mut ConversationFeed) -> Result<()> {
    let reader = feed.reader().clone();
    feed.request_close();
    reader.request_close();
    let (feed, reader) = tokio::join!(feed.close(), reader.close());
    feed?;
    reader
}

#[tokio::test]
async fn completed_tool_and_skill_activation_are_public_before_the_turn_is_cancelled() -> Result<()>
{
    let stage = ReplyStage::new();
    let env = Environment::new(
        vec![
            prompt_step(
                PROMPT,
                0,
                program_reply("skill_view", CALL, serde_json::json!({"name": SKILL})),
            ),
            Step::tool_output(
                Protocol::ResponsesHttp,
                CALL,
                "# Canvas design",
                1,
                held_reply(&stage, "held-after-skill"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let started = env.start(ThreadWorkspaceMode::Local, PROMPT).await?;
        let thread_id = &started.thread.id;
        reached(&stage).await?;
        let snapshot = env.runtime.thread_snapshot(thread_id).await?;
        let turn = snapshot.active_turn.as_ref().context("original active Turn")?;
        let input_id = format!("input-{PROMPT}");
        ensure!(turn.input_id.as_deref() == Some(input_id.as_str()));
        ensure!(matches!(turn.state, TurnState::Running(_)));
        let turn_id = turn.id.clone();
        let runtime = snapshot.runtime.as_ref().context("runtime projection")?;
        let execution_id = runtime.execution.as_ref().context("original execution")?.id().to_owned();
        ensure!(runtime.active_skills.iter().any(|name| name == SKILL));
        // The State snapshot supplies the actual Turn independently of Activity
        // and completion history. Successful Turn receipts are hidden from Main.
        let mut main = env.runtime.open_conversation_state_feed(thread_id)
            .await.context("open current Turn's public Main head")?;
        let parent_id = tokio::time::timeout(DEADLINE, async {
            loop {
                let event = main.recv().await?.context("Main ended before State")?;
                if let pl_protocol::ThreadSubscriptionUpdate::Snapshot {
                        completed_history_version,
                        snapshot,
                    } = event
                {
                    ensure!(completed_history_version == pl_protocol::COMPLETED_HISTORY_VERSION);
                    if let Some(head) = snapshot.active_turn
                        && head.id == turn_id
                    {
                        let parent = pl_core::chat::ChatKey::new("turn", &head.id)?
                            .as_str().to_owned();
                        return Ok::<_, anyhow::Error>(parent);
                    }
                }
            }
        }).await.context("public active Turn head did not arrive");
        let main_closed = main.close().await;
        let parent_id = parent_id
            .with_context(|| format!("Main feed close: {main_closed:?}"))?
            .with_context(|| format!("Main feed close: {main_closed:?}"))?;
        main_closed?;
        let scope = ChatScope::conversation(Some(parent_id));
        // The following provider request proves admission to model context, not a durable
        // writer barrier. Derive the authored child preview from that selected typed receipt;
        // publication and cancellation are then checked through the public conversation reader.
        let viewed: Value = serde_json::from_str(&support::tool_output(&env.root_provider, CALL)?)?;
        let expected_output = format!("Skill: {}\nResource: {}\n\n{}",
            viewed["skill"]["name"].as_str().context("viewed skill name")?,
            viewed["filePath"].as_str().context("viewed skill file")?,
            viewed["content"].as_str().context("viewed skill content")?);


        let mut feed = env.runtime.open_conversation_feed(thread_id, scope.clone(), demand()).await
            .context("open the original active Turn's Children")?;
        let observed = async {
            let members = live_members(&mut feed).await?;
            let tools = members.iter().filter(|(_, payload)| {
                payload["type"] == "tool" && payload["data"]["invocation"]["callId"].as_str().is_some_and(|id| id.starts_with(&format!("{CALL}:nested:")))
            }).collect::<Vec<_>>();
            ensure!(tools.len() == 1, "original completed tool was not publicly readable");
            let (tool_id, tool) = tools[0];
            ensure!(tool["turnId"] == turn_id && tool["data"]["state"]["kind"] == "succeeded");
            let tool_call_id = tool["data"]["invocation"]["toolCallId"].as_str().context("tool identity")?;
            let skills = members.iter().filter(|(_, payload)| payload["type"] == "skill")
                .collect::<Vec<_>>();
            ensure!(skills.len() == 1, "activation was not publicly readable during the Turn");
            let (skill_id, skill) = skills[0];
            let activated: ThreadSkillItem = serde_json::from_value(skill["data"].clone())?;
            ensure!(skill["turnId"] == turn_id);
            ensure!(activated.activation().turn_id == turn_id && activated.activation().name == SKILL);
            ensure!(matches!(&activated.activation().cause, SkillActivationCause::Tool { tool_call_id: cause }
                if cause == tool_call_id));
            let manifest = feed.reader().list_contents(tool_id, None, demand()).await?;
            let result = manifest.entries.iter().find(|entry| entry.key == "tool.result")
                .context("original tool result manifest")?;
            let actual = read_sealed(feed.reader(), &result.reference, expected_output.len() as u64).await?;
            ensure!(actual == expected_output.as_bytes(), "public result was truncated or changed");
            let still_running = env.runtime.thread_snapshot(thread_id).await?;
            ensure!(still_running.active_turn.as_ref().is_some_and(|turn|
                turn.id == turn_id && matches!(turn.state, TurnState::Running(_))));
            Ok::<_, anyhow::Error>(BTreeMap::from([
                (tool_id.clone(), tool.clone()),
                (skill_id.clone(), skill.clone()),
            ]))
        }.await;
        let closed = close_feed(&mut feed).await;
        let observed = observed.with_context(|| format!("original feed close: {closed:?}"))?;
        closed?;

        env.runtime.stop_thread(thread_id.clone(), StopThreadRequest {
            operation_id: "stop-held-skill-execution".into(),
            expected_execution_id: execution_id,
        }).await?;
        let terminal = support::completed_prompt(&env.runtime, thread_id, PROMPT).await?;
        ensure!(terminal.id == turn_id && matches!(terminal.state, TurnState::Cancelled(_)));
        stage.release();

        let mut reopened = env.runtime.open_conversation_feed(thread_id, scope, demand()).await
            .context("reopen the original cancelled Turn's Children")?;
        let checked = async {
            let after = original_members(&mut reopened).await?;
            for (id, payload) in observed {
                ensure!(after.get(&id) == Some(&payload), "cancellation rewrote a completed member");
            }
            let runtime = env.runtime.thread_snapshot(thread_id).await?.runtime.context("post-cancel runtime")?;
            ensure!(runtime.active_skills.iter().any(|name| name == SKILL));
            Ok(())
        }.await;
        let closed = close_feed(&mut reopened).await;
        checked.with_context(|| format!("reopened feed close: {closed:?}"))?;
        closed
    }.await;
    // This also releases the fixture on failures, before joining the real Runtime/provider owners.
    stage.release();
    env.finish(result).await
}
