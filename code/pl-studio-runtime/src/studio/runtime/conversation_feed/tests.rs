use super::*;
use anyhow::{Context, Result, bail};
use pl_core::chat::ChatKey;
use pl_provider_fixture::{Protocol, Reply, ReplyStage, RequestMatch, Step};
use std::{collections::HashMap, time::Duration};

use crate::runtime_test_support as support;
mod allocation;
mod coalescing;
mod completed_runs;
mod state_activity;

#[derive(serde::Deserialize, schemars::JsonSchema)]
struct EchoArgs {
    message: String,
}

#[derive(Clone, Default)]
struct BindingCounts {
    echo: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    fail: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    serialized: std::sync::Arc<std::sync::atomic::AtomicUsize>,
}

// Deliberately Serialize-only: history must not need today's Rust output type.
struct EchoOutput {
    text: String,
    serialized: std::sync::Arc<std::sync::atomic::AtomicUsize>,
}

impl serde::Serialize for EchoOutput {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        self.serialized
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let mut output = serializer.serialize_struct("EchoOutput", 1)?;
        output.serialize_field("text", &self.text)?;
        output.end()
    }
}

struct JsonEchoTool(BindingCounts);

impl pl_agent_tool::typed::TypedTool for JsonEchoTool {
    const NAME: &'static str = "json_echo";
    const DESCRIPTION: &'static str = "Echo a message as a typed JSON result.";
    type Args = EchoArgs;
    type Context = ();
    type Output = EchoOutput;
    type Error = std::convert::Infallible;

    async fn execute(&self, args: EchoArgs, (): ()) -> Result<EchoOutput, Self::Error> {
        self.0
            .echo
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(EchoOutput {
            text: args.message,
            serialized: self.0.serialized.clone(),
        })
    }
}

struct FailSerializeOutput(std::sync::Arc<std::sync::atomic::AtomicUsize>);

impl serde::Serialize for FailSerializeOutput {
    fn serialize<S: serde::Serializer>(&self, _serializer: S) -> Result<S::Ok, S::Error> {
        self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Err(serde::ser::Error::custom(
            "fixture output serializer failed",
        ))
    }
}

struct FailSerializeTool(BindingCounts);

impl pl_agent_tool::typed::TypedTool for FailSerializeTool {
    const NAME: &'static str = "fail_serialize";
    const DESCRIPTION: &'static str = "Complete a side effect, then fail output encoding.";
    type Args = EchoArgs;
    type Context = ();
    type Output = FailSerializeOutput;
    type Error = std::convert::Infallible;

    async fn execute(&self, _args: EchoArgs, (): ()) -> Result<FailSerializeOutput, Self::Error> {
        self.0
            .fail
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(FailSerializeOutput(self.0.serialized.clone()))
    }
}

fn json_binding_registrations(
    counts: &BindingCounts,
) -> Result<Vec<pl_core::tool::opaque::Registration>> {
    use pl_agent_tool::ToolHandle;
    use pl_core::tool::opaque::ToolError;
    use pl_tool::binding::{ToolCallPolicy, prepare_json_tool, prepare_registration};

    let echo = prepare_json_tool::<JsonEchoTool>(|_| (), ToolError::new)?;
    let echo_registration = prepare_registration(
        "fixture.echo",
        echo.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    let fail = prepare_json_tool::<FailSerializeTool>(|_| (), ToolError::new)?;
    let fail_registration = prepare_registration(
        "fixture.fail",
        fail.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    Ok(vec![
        echo_registration.attach(ToolHandle::new(echo.attach(JsonEchoTool(counts.clone())))),
        fail_registration.attach(ToolHandle::new(
            fail.attach(FailSerializeTool(counts.clone())),
        )),
    ])
}

async fn binding_content(
    reader: &ConversationReader,
    reference: &ContentRef,
    length: u64,
) -> Result<Vec<u8>> {
    anyhow::ensure!(length <= 1024 * 1024, "fixture content exceeded its bound");
    let mut bytes = Vec::new();
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
        assert_eq!(window.offset, offset);
        assert!(window.sealed && !window.bytes.is_empty());
        assert_eq!(window.available_through, length);
        bytes.extend(window.bytes);
    }
    assert_eq!(bytes.len() as u64, length);
    Ok(bytes)
}

async fn binding_tool_payloads(
    feed: &mut ConversationFeed,
) -> Result<HashMap<String, serde_json::Value>> {
    let mut batch = chat(feed).await?;
    let mut tools = HashMap::new();
    loop {
        for entry in batch.entries {
            let atom = entry.atom;
            let bytes = match atom.payload.context("completed activity payload")? {
                PayloadData::Inline { bytes } => bytes,
                PayloadData::Deferred {
                    reference,
                    byte_length,
                } => binding_content(feed.reader(), &reference, byte_length).await?,
            };
            let payload: serde_json::Value = serde_json::from_slice(&bytes)?;
            if payload["type"] == "tool" {
                assert_eq!(payload["contract"], "anywork.chat/1");
                let call = payload["data"]["invocation"]["callId"]
                    .as_str()
                    .context("tool call ID")?
                    .to_owned();
                assert!(tools.insert(call, payload).is_none());
            }
        }
        let Some(before) = batch.before else { break };
        batch = feed.reader().load_older(&before, demand()).await?;
    }
    Ok(tools)
}

async fn binding_body(
    reader: &ConversationReader,
    payload: &serde_json::Value,
    key: &str,
) -> Result<Vec<u8>> {
    let body = payload["bodies"]
        .as_array()
        .context("tool bodies")?
        .iter()
        .find(|body| body["key"] == key)
        .with_context(|| format!("missing {key}"))?;
    if let Some(inline) = body.get("inline") {
        return Ok(serde_json::from_value(inline.clone())?);
    }
    let reference = serde_json::from_value(body["reference"].clone())?;
    binding_content(
        reader,
        &reference,
        body["byteLength"].as_u64().context("body byte length")?,
    )
    .await
}

#[tokio::test]
async fn json_echo_binding_survives_cold_read() -> Result<()> {
    use pl_core::{
        context::ContextContent,
        thread::{ModelStepLimit, ToolOutcome, TurnInput},
    };
    use pl_provider_fixture::RealtimeToolCall;
    use std::sync::{Arc, atomic::Ordering};

    let message = "原样保存中文正文📖".repeat(1600);
    let arguments = format!(" {{ \"message\" : {} }} ", serde_json::to_string(&message)?);
    let expected = serde_json::json!({"text": message}).to_string();
    let prompt = "binding-echo";
    let call = "binding-echo-call";
    let mut env = support::Environment::new(
        vec![
            support::prompt_step(
                "binding-warmup",
                0,
                support::text_reply("ready", "binding-ready"),
            ),
            support::prompt_step(
                prompt,
                1,
                Reply::Sse(pl_provider_fixture::responses_tool_calls(
                    call,
                    support::MODEL,
                    &[RealtimeToolCall {
                        item_id: call,
                        call_id: call,
                        name: "json_echo",
                        arguments: arguments.clone(),
                    }],
                )),
            ),
            support::prompt_step(
                prompt,
                2,
                support::text_reply("echo delivered", "binding-done"),
            ),
        ],
        vec![],
    )
    .await?;
    let counts = BindingCounts::default();
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "binding-warmup")
            .await?;
        let id = &thread.thread.id;
        support::completed_prompt(&env.runtime, id, "binding-warmup").await?;
        // The test owns the replacement catalog, not the production catalog refresher.
        // Join its workers before installing the binding so a pending warmup refresh cannot
        // revoke the frozen fixture tools while the real provider request is running.
        env.runtime.stop_tool_refresh().await?;
        let handle = env
            .runtime
            .session_of(id)
            .and_then(|session| session.thread(id))
            .context("real Thread owner")?;
        handle
            .register_tools(json_binding_registrations(&counts)?)
            .await?;
        handle
            .run_turn(TurnInput {
                turn_id: "binding-echo-turn".into(),
                attempt_prefix: "binding-echo-attempt".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from(prompt),
                }],
                max_model_steps: ModelStepLimit::Unlimited,
                cancellation: Default::default(),
            })
            .await?;
        assert_eq!(
            support::tool_output(&env.root_provider, call)?.as_bytes(),
            expected.as_bytes()
        );
        env.runtime.require_session(id)?.close(id).await?;
        drop(handle);
        env.restart().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        let durable = env
            .runtime
            .store
            .history(id)
            .await?
            .tool_task(&format!("task:{call}"))
            .await?
            .context("durable echo")?;
        let delivery = durable.delivery.context("complete echo delivery")?;
        assert!(matches!(delivery.outcome, ToolOutcome::Succeeded));
        assert_eq!(delivery.tool_id, "fixture.echo");
        assert_eq!(delivery.output.payload().format(), "application/json");
        assert_eq!(delivery.output.payload().version(), 1);
        assert_eq!(
            delivery.output.payload().content().as_bytes(),
            expected.as_bytes()
        );
        assert_eq!(
            delivery.delivered_context,
            vec![ContextContent::Text {
                text: Arc::from(expected.clone())
            }]
        );
        assert_eq!(delivery.output.context(), delivery.delivered_context);
        let mut feed = env
            .runtime
            .open_conversation_feed(
                id,
                ChatScope::Children {
                    parent_id: ChatKey::new("turn", "binding-echo-turn")?.as_str().into(),
                },
                demand(),
            )
            .await?;
        let tools = binding_tool_payloads(&mut feed).await?;
        let payload = tools.get(call).context("cold tool activity")?;
        assert_eq!(
            payload["data"]["invocation"]["presentationContract"],
            "generic@1"
        );
        assert_eq!(
            binding_body(feed.reader(), payload, "tool.arguments").await?,
            arguments.as_bytes()
        );
        assert_eq!(
            binding_body(feed.reader(), payload, "tool.result").await?,
            expected.as_bytes()
        );
        for key in ["tool.arguments", "tool.result"] {
            assert!(
                payload["bodies"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|body| body["key"] == key && body.get("reference").is_some())
            );
        }
        feed.close().await?;
        feed.reader().close().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none(),
            "cold read activated owner"
        );
        assert_eq!(counts.echo.load(Ordering::SeqCst), 1);
        assert_eq!(counts.fail.load(Ordering::SeqCst), 0);
        assert_eq!(counts.serialized.load(Ordering::SeqCst), 1);
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn json_output_encoding_failure_is_not_reexecuted() -> Result<()> {
    use pl_core::{
        context::ContextContent,
        thread::{ModelStepLimit, ToolOutcome, TurnInput},
    };
    use pl_provider_fixture::RealtimeToolCall;
    use std::sync::{Arc, atomic::Ordering};

    let invalid = " { \"message\" : 7 } ";
    let valid = " { \"message\" : \"执行一次后编码失败\" } ";
    let prompt = "binding-failures";
    let mut env = support::Environment::new(
        vec![
            support::prompt_step(
                "binding-failure-warmup",
                0,
                support::text_reply("ready", "failure-ready"),
            ),
            support::prompt_step(
                prompt,
                1,
                Reply::Sse(pl_provider_fixture::responses_tool_calls(
                    "binding-failures",
                    support::MODEL,
                    &[
                        RealtimeToolCall {
                            item_id: "bad-args",
                            call_id: "bad-args",
                            name: "json_echo",
                            arguments: invalid.into(),
                        },
                        RealtimeToolCall {
                            item_id: "bad-output",
                            call_id: "bad-output",
                            name: "fail_serialize",
                            arguments: valid.into(),
                        },
                    ],
                )),
            ),
            support::prompt_step(
                prompt,
                2,
                support::text_reply("failures delivered", "failure-done"),
            ),
        ],
        vec![],
    )
    .await?;
    let counts = BindingCounts::default();
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "binding-failure-warmup")
            .await?;
        let id = &thread.thread.id;
        support::completed_prompt(&env.runtime, id, "binding-failure-warmup").await?;
        // Quiesce the competing catalog writer, retaining the real Thread/storage owners.
        env.runtime.stop_tool_refresh().await?;
        let handle = env
            .runtime
            .session_of(id)
            .and_then(|session| session.thread(id))
            .context("real Thread owner")?;
        handle
            .register_tools(json_binding_registrations(&counts)?)
            .await?;
        handle
            .run_turn(TurnInput {
                turn_id: "binding-failure-turn".into(),
                attempt_prefix: "binding-failure-attempt".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from(prompt),
                }],
                max_model_steps: ModelStepLimit::Unlimited,
                cancellation: Default::default(),
            })
            .await?;
        env.runtime.require_session(id)?.close(id).await?;
        drop(handle);
        env.restart().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        let mut feed = env
            .runtime
            .open_conversation_feed(
                id,
                ChatScope::Children {
                    parent_id: ChatKey::new("turn", "binding-failure-turn")?
                        .as_str()
                        .into(),
                },
                demand(),
            )
            .await?;
        let tools = binding_tool_payloads(&mut feed).await?;
        for (call, arguments) in [("bad-args", invalid), ("bad-output", valid)] {
            let durable = env
                .runtime
                .store
                .history(id)
                .await?
                .tool_task(&format!("task:{call}"))
                .await?
                .context("durable failure")?;
            assert_eq!(
                durable.task.status,
                pl_core::thread::task::TaskStatus::Failed
            );
            let delivery = durable.delivery.context("failed delivery")?;
            let ToolOutcome::Failed(error) = &delivery.outcome else {
                bail!("expected Failed")
            };
            let text = error.to_string();
            if call == "bad-output" {
                assert!(
                    text.contains("returned successfully")
                        && text.contains("side effects may have occurred")
                        && text.contains("did not retry")
                );
                assert!(text.contains("output JSON encoding failed"));
                let mut source = std::error::Error::source(error.as_ref());
                let mut found = false;
                while let Some(error) = source {
                    found |= error
                        .to_string()
                        .contains("fixture output serializer failed");
                    source = error.source();
                }
                assert!(found, "serializer source was not saved");
            } else {
                assert!(
                    text.contains("message") && text.contains("string"),
                    "{text}"
                );
            }
            let projected = delivery
                .delivered_context
                .iter()
                .filter_map(|content| {
                    if let ContextContent::Text { text } = content {
                        Some(text.as_ref())
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
                .join("");
            assert_eq!(support::tool_output(&env.root_provider, call)?, projected);
            assert!(projected.contains(if call == "bad-output" {
                "side effects may have occurred"
            } else {
                "string"
            }));
            let payload = tools.get(call).context("cold failed activity")?;
            assert_eq!(
                payload["data"]["invocation"]["presentationContract"],
                "generic@1"
            );
            assert_eq!(payload["data"]["state"]["kind"], "failed");
            assert_eq!(
                binding_body(feed.reader(), payload, "tool.arguments").await?,
                arguments.as_bytes()
            );
        }
        feed.close().await?;
        feed.reader().close().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        assert_eq!(counts.echo.load(Ordering::SeqCst), 0);
        assert_eq!(counts.fail.load(Ordering::SeqCst), 1);
        assert_eq!(counts.serialized.load(Ordering::SeqCst), 1);
        Ok(())
    }
    .await;
    env.finish(result).await
}

async fn chat(feed: &mut ConversationFeed) -> Result<ChatBatch> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            match feed.recv().await?.context("feed ended")? {
                ConversationEvent::Chat { batch } => {
                    batch.validate_for(&feed.reader.inner.scope)?;
                    assert!(
                        batch.entries.len() <= feed.demand.max_items as usize,
                        "total scope entries exceeded the caller's item budget"
                    );
                    assert!(batch.encoded_len()? <= feed.demand.max_bytes as usize);
                    return Ok(*batch);
                }
                ConversationEvent::State { .. } | ConversationEvent::Activity { .. } => {}
            }
        }
    })
    .await?
}
fn demand() -> ReadDemand {
    ReadDemand {
        max_items: 8,
        max_bytes: 128 * 1024,
    }
}

fn question_steps(prompt: &str, first: Reply) -> Vec<Step> {
    vec![
        support::prompt_step(prompt, 0, first),
        Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::InteractionAnswers {
                text: serde_json::json!({
                    "answers": {
                        "provider": {
                            "answers": ["fixture-answer"]
                        }
                    }
                })
                .to_string(),
                step: 1,
            },
            reply: support::text_reply("question resolved", "question-resolved"),
            optional: false,
        },
    ]
}

fn question_reply(call_id: &str) -> Reply {
    support::tool_reply(
        "request_user_input",
        call_id,
        serde_json::json!({
            "questions": [{
                "id": "provider",
                "header": "Provider",
                "question": "Which provider should the next release verify?",
                "isOther": true
            }]
        }),
    )
}

fn answer() -> InteractionResolution {
    InteractionResolution::UserInput(UserInputResolution {
        answers: HashMap::from([(
            "provider".into(),
            UserInputAnswer {
                answers: vec!["fixture-answer".into()],
            },
        )]),
    })
}

async fn initial_snapshot(feed: &mut ConversationFeed) -> Result<ThreadSnapshot> {
    let ConversationEvent::Chat { batch } = feed.recv().await?.context("missing initial Chat")?
    else {
        bail!("conversation must start with Chat");
    };
    assert_eq!(batch.placement, ChatPlacement::Set);
    let ConversationEvent::State { update } =
        feed.recv().await?.context("missing initial State")?
    else {
        bail!("Chat Set must be followed by State");
    };
    let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = *update else {
        bail!("first State must be a snapshot");
    };
    Ok(*snapshot)
}

fn assert_notification_revision(notification: &ThreadNotificationEnvelope, revision: &mut u64) {
    assert_eq!(notification.base_revision, *revision);
    assert_eq!(notification.revision, *revision + 1);
    *revision = notification.revision;
}

async fn finish_question(
    feed: &mut ConversationFeed,
    interaction_id: &str,
    pending_revision: u64,
    mut revision: u64,
    pending: &mut usize,
    resolved: &mut usize,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            match feed
                .recv()
                .await?
                .context("feed ended before terminal State")?
            {
                ConversationEvent::Chat { .. } | ConversationEvent::Activity { .. } => {}
                ConversationEvent::State { update } => {
                    let ThreadSubscriptionUpdate::Notification { notification } = *update else {
                        bail!("live question flow emitted a second State snapshot");
                    };
                    assert_notification_revision(&notification, &mut revision);
                    match notification.notification {
                        ThreadNotification::InteractionChanged { interaction }
                            if interaction.interaction_id == interaction_id =>
                        {
                            match interaction.status() {
                                InteractionStatus::Pending => {
                                    assert_eq!(interaction.revision, pending_revision);
                                    *pending += 1;
                                }
                                InteractionStatus::Resolved => {
                                    assert_eq!(interaction.revision, pending_revision + 1);
                                    *resolved += 1;
                                }
                                status => bail!("question reached unexpected status {status:?}"),
                            }
                        }
                        ThreadNotification::TurnCompleted { .. } if *resolved == 1 => {
                            return Ok(());
                        }
                        _ => {}
                    }
                }
            }
        }
    })
    .await
    .context("finite question scenario did not reach terminal State")?
}

async fn published_pending(
    env: &support::Environment,
    thread_id: &str,
) -> Result<(InteractionRequest, u64)> {
    let slot = env.runtime.thread_observations.observation_slot(thread_id);
    let (position, _) = slot.capture();
    let source = position
        .source
        .context("running Thread has no live owner")?;
    let mut changed = source.content_changes();
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let Some(current) = source
                .current_conversation()
                .map(|value| value.current.clone())
                && let Some(interaction) = current
                    .interactions()
                    .iter()
                    .find(|interaction| interaction.status() == InteractionStatus::Pending)
            {
                return Ok::<_, anyhow::Error>((
                    interaction.clone(),
                    current.projection().source_effect_seq,
                ));
            }
            changed
                .changed()
                .await
                .context("live publication ended before the pending question")?;
        }
    })
    .await
    .context("pending question was not published by the live owner")?
}

#[tokio::test]
async fn question_cut_late_open_starts_with_published_pending_and_delivers_one_answer() -> Result<()>
{
    let env = support::Environment::new(
        question_steps("late-question", question_reply("late-question-call")),
        vec![],
    )
    .await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "late-question")
            .await?;
        let id = &thread.thread.id;
        let (pending, publication_revision) = published_pending(&env, id).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let snapshot = initial_snapshot(&mut feed).await?;
        assert_eq!(snapshot.revision, publication_revision);
        assert_eq!(
            snapshot.interactions.as_slice(),
            std::slice::from_ref(&pending),
            "first State did not use the canonical owner cut"
        );
        assert_eq!(pending.status(), InteractionStatus::Pending);

        env.runtime
            .resolve_interaction(
                "late-question-answer".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                answer(),
            )
            .await?;
        let mut repeated_pending = 0;
        let mut resolved = 0;
        finish_question(
            &mut feed,
            &pending.interaction_id,
            pending.revision,
            snapshot.revision,
            &mut repeated_pending,
            &mut resolved,
        )
        .await?;
        assert_eq!(
            repeated_pending, 0,
            "baseline pending question was notified again"
        );
        assert_eq!(resolved, 1);
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn question_cut_open_feed_delivers_new_pending_and_answer_once_in_order() -> Result<()> {
    let stage = ReplyStage::new();
    let Reply::Sse(frames) = question_reply("live-question-call") else {
        unreachable!("question fixture uses SSE")
    };
    let first = stage.gated(vec![frames[0].clone()], frames[1..].to_vec());
    let env = support::Environment::new(question_steps("live-question", first), vec![]).await?;
    let result = async {
        let thread = env
            .start(ThreadWorkspaceMode::Local, "live-question")
            .await?;
        let id = &thread.thread.id;
        support::reached(&stage).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let snapshot = initial_snapshot(&mut feed).await?;
        assert!(
            snapshot.interactions.is_empty(),
            "held tool interaction entered the initial cut"
        );
        stage.release();

        let mut state_revision = snapshot.revision;
        let pending = tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                match feed
                    .recv()
                    .await?
                    .context("feed ended before pending question")?
                {
                    ConversationEvent::Chat { .. } | ConversationEvent::Activity { .. } => {}
                    ConversationEvent::State { update } => {
                        let ThreadSubscriptionUpdate::Notification { notification } = *update
                        else {
                            bail!("live question flow emitted a second State snapshot");
                        };
                        assert_notification_revision(&notification, &mut state_revision);
                        if let ThreadNotification::InteractionChanged { interaction } =
                            notification.notification
                            && interaction.status() == InteractionStatus::Pending
                        {
                            return Ok::<_, anyhow::Error>(interaction);
                        }
                    }
                }
            }
        })
        .await
        .context("live pending question was not delivered")??;
        let pending_refs = feed.reader().read_business_refs().await?;
        let pending_resource = pending_refs
            .interactions
            .context("pending interaction resource")?;
        let first_page = feed
            .reader()
            .page_current(
                &pending_resource,
                None,
                ReadDemand {
                    max_items: 1,
                    ..demand()
                },
            )
            .await?;
        assert_eq!(first_page.entries.len(), 1);
        let mut pending_count = 1;
        let mut resolved = 0;
        env.runtime
            .resolve_interaction(
                "live-question-answer".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                answer(),
            )
            .await?;
        finish_question(
            &mut feed,
            &pending.interaction_id,
            pending.revision,
            state_revision,
            &mut pending_count,
            &mut resolved,
        )
        .await?;
        assert_eq!(pending_count, 1);
        assert_eq!(resolved, 1);
        assert!(
            feed.reader()
                .page_current(
                    &pending_resource,
                    first_page.continuation.as_deref(),
                    demand()
                )
                .await
                .is_err(),
            "old interaction revision silently read a newer collection"
        );
        let current_refs = feed.reader().read_business_refs().await?;
        assert_ne!(current_refs.interactions.as_ref(), Some(&pending_resource));
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

async fn state_snapshot(feed: &mut ConversationFeed) -> Result<Box<ThreadSnapshot>> {
    let ConversationEvent::State { update } =
        feed.recv().await?.context("missing State baseline")?
    else {
        bail!("Set must be followed by the State baseline");
    };
    let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = *update else {
        bail!("first State must be a snapshot");
    };
    Ok(snapshot)
}

#[tokio::test]
async fn pending_plan_is_delivered_live_and_restored_on_hot_and_cold_open() -> Result<()> {
    let plan = format!("# 待确认计划\n\n{}", "步骤\n".repeat(9000));
    let stage = ReplyStage::new();
    let Reply::Sse(frames) = support::tool_reply(
        "plan_submit",
        "feed-plan",
        serde_json::json!({
            "expectedRevision": 0, "plan": plan,
        }),
    ) else {
        bail!("expected SSE tool reply")
    };
    let first = stage.gated(frames[..1].to_vec(), frames[1..].to_vec());
    let mut env = support::Environment::new(
        vec![
            support::prompt_step("pending-plan-feed", 0, first),
            support::prompt_step(
                &plan,
                1,
                support::text_reply("approved and continued", "after-plan"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        // The long Plan crosses the storage chunk boundary. Keep its continuation within the
        // fixture's declared window so this journey does not require a compaction response.
        let config_store =
            crate::config::ConfigStore::new(crate::config::ConfigPaths::from_config_dir(&env.home));
        let mut config = config_store.load()?;
        let account = config
            .models
            .accounts
            .get_mut(&pl_model::config::AccountId::new("root-fixture")?)
            .context("root fixture account")?;
        let pl_model::config::AccountModelCatalogConfig::Explicit { models, .. } =
            &mut account.catalog
        else {
            bail!("fixture account must have an explicit model catalog");
        };
        let model = models
            .iter_mut()
            .find(|model| model.model_id == support::MODEL)
            .context("root fixture model")?;
        model.context_window = Some(256_000);
        model.max_context_window = Some(256_000);
        model.max_output_tokens = Some(32_000);
        config_store.save(&config)?;
        env.restart().await?;
        let started = env
            .start(ThreadWorkspaceMode::Local, "pending-plan-feed")
            .await?;
        let id = &started.thread.id;
        support::reached(&stage).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut live).await?.placement, ChatPlacement::Set);
        assert!(state_snapshot(&mut live).await?.interactions.is_empty());
        stage.release();
        let pending = tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(event) = live.recv().await? {
                if let ConversationEvent::State { update } = event
                    && let ThreadSubscriptionUpdate::Notification { notification } = *update
                    && let ThreadNotification::InteractionChanged { interaction } =
                        notification.notification
                    && interaction.status() == InteractionStatus::Pending
                {
                    return Ok::<_, anyhow::Error>(*interaction);
                }
            }
            bail!("Plan submission did not publish its pending interaction");
        })
        .await??;
        assert!(matches!(
            pending.scope.purpose,
            InteractionPurpose::AgentSessionPlanConfirmation(_)
        ));
        assert!(
            serde_json::to_vec(&pending)?.len() > 64 * 1024,
            "cold restore must read multiple content chunks"
        );
        let completed = support::completed_prompt(&env.runtime, id, "pending-plan-feed").await?;
        assert!(matches!(completed.state, TurnState::Completed(_)));
        live.close().await?;
        live.reader().close().await?;

        let mut reopened = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut reopened).await?.placement, ChatPlacement::Set);
        let baseline = state_snapshot(&mut reopened).await?;
        assert_eq!(baseline.interactions, vec![pending.clone()]);
        assert_eq!(
            reopened.reader().read_business_refs().await?,
            baseline.business_refs
        );
        let document = baseline
            .business_refs
            .plan
            .as_ref()
            .context("Plan read head")?
            .document
            .as_ref()
            .context("Plan document reference")?;
        let window = reopened
            .reader()
            .read_content(
                document,
                ContentRange {
                    offset: 0,
                    max_bytes: 4096,
                },
            )
            .await?;
        assert_eq!(window.bytes, plan.as_bytes()[..4096]);
        let reference = baseline
            .business_refs
            .interactions
            .as_ref()
            .context("interaction read resource")?;
        let page = reopened
            .reader()
            .page_current(reference, None, demand())
            .await?;
        assert_eq!(page.entries.len(), 1);
        assert_eq!(page.entries[0].id, pending.interaction_id);
        reopened.close().await?;
        reopened.reader().close().await?;

        env.restart().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        let mut cold = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut cold).await?.placement, ChatPlacement::Set);
        let baseline = state_snapshot(&mut cold).await?;
        assert!(
            baseline.activity.is_none(),
            "cold read invented execution activity"
        );
        assert_eq!(baseline.interactions, vec![pending.clone()]);
        assert_eq!(
            cold.reader().read_business_refs().await?,
            baseline.business_refs
        );
        let document = baseline
            .business_refs
            .plan
            .as_ref()
            .context("Plan read head")?
            .document
            .as_ref()
            .context("Plan document reference")?;
        let window = cold
            .reader()
            .read_content(
                document,
                ContentRange {
                    offset: 0,
                    max_bytes: 4096,
                },
            )
            .await?;
        assert_eq!(window.bytes, plan.as_bytes()[..4096]);
        let reference = baseline
            .business_refs
            .interactions
            .as_ref()
            .context("interaction read resource")?;
        let page = cold
            .reader()
            .page_current(reference, None, demand())
            .await?;
        assert_eq!(page.entries.len(), 1);
        assert_eq!(page.entries[0].id, pending.interaction_id);
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none(),
            "reading a pending Plan activated execution"
        );
        assert_eq!(env.root_provider.recorded().len(), 1);
        cold.close().await?;
        cold.reader().close().await?;

        let mut continuation = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: id.clone(),
            })
            .await?;
        let resolved = env
            .runtime
            .resolve_interaction(
                "approve-feed-plan".into(),
                id.clone(),
                pending.revision,
                pending.interaction_id.clone(),
                InteractionResolution::UserInput(UserInputResolution {
                    answers: [(
                        AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                        UserInputAnswer {
                            answers: vec!["Approve".into()],
                        },
                    )]
                    .into(),
                }),
            )
            .await?;
        assert_eq!(resolved.interaction.status(), InteractionStatus::Resolved);
        tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(update) = continuation.recv().await? {
                if let ThreadSubscriptionUpdate::Notification { notification } = update
                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                    && turn.id != completed.id
                {
                    anyhow::ensure!(
                        matches!(turn.state, TurnState::Completed(_)),
                        "approved continuation failed: {:?}",
                        turn.state
                    );
                    return Ok::<_, anyhow::Error>(());
                }
            }
            bail!("approved Plan did not complete its continuation");
        })
        .await??;
        drop(continuation);
        assert_eq!(env.root_provider.recorded().len(), 2);
        let mut approved = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut approved).await?.placement, ChatPlacement::Set);
        assert!(
            state_snapshot(&mut approved).await?.interactions.is_empty(),
            "answered Plan returned as pending"
        );
        approved.close().await?;
        approved.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn retained_terminal_state_requires_coverage_and_no_active_turn_and_is_deduplicated()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "retained State qualification")
            .await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut feed).await?.placement, ChatPlacement::Set);
        let _snapshot = feed.recv().await?.context("initial State snapshot")?;
        completed_runs::activity(&mut feed).await?;
        assert!(feed.pending.is_empty());
        let uncovered = feed
            .state_effect_floor
            .checked_add(1)
            .context("test State cut exhausted")?;
        let terminal = Turn {
            input_id: Some("original-input".into()),
            id: "original-turn".into(),
            thread_id: thread.id.clone(),
            revision: uncovered,
            state: TurnState::Completed(CompletedTurnState::new(
                Some(1),
                2,
                TurnCompletion::Normal,
            )),
            updated_at: 2,
        };
        let revision = feed.state_revision;
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "future terminal crossed the cut");
        assert_eq!(feed.state_revision, revision);

        feed.state_effect_floor = terminal.revision;
        feed.active_turn = Some("newer-active-turn".into());
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "older terminal hid an active Turn");
        assert_eq!(feed.state_revision, revision);

        feed.active_turn = None;
        feed.reflect_terminal(terminal.clone())?;
        assert_eq!(feed.pending.len(), 1);
        assert_eq!(feed.state_revision, revision + 1);
        feed.reflect_terminal(terminal.clone())?;
        feed.state_event(ThreadLiveEvent::Committed {
            sequence: terminal.revision + 1,
            changes: vec![LiveEvent::Turn {
                turn: terminal.clone(),
                event: TurnEvent::Completed,
            }],
        })?;
        assert_eq!(
            feed.pending.len(),
            1,
            "retained/live duplicate spent a frame"
        );
        assert_eq!(feed.state_revision, revision + 1);

        let newer = Turn {
            revision: terminal.revision + 1,
            ..terminal
        };
        feed.reflect_terminal(newer)?;
        assert_eq!(feed.pending.len(), 2, "newer same-Turn fact was suppressed");
        assert_eq!(feed.state_revision, revision + 2);
        feed.state_event(ThreadLiveEvent::UnframedCommit {
            sequence: feed.state_effect_floor,
        })?;
        assert_eq!(feed.pending.len(), 2, "covered gap spent a State frame");
        assert_eq!(feed.state_revision, revision + 2);
        for _ in 0..2 {
            assert!(matches!(
                feed.recv().await?,
                Some(ConversationEvent::State { .. })
            ));
        }
        let (events, state) = tokio::sync::broadcast::channel(1);
        feed.state = Some(super::super::thread_observation::StateReceiver::new(
            state,
            Default::default(),
        ));
        feed.state_turn = true;
        events.send(ThreadLiveEvent::UnframedCommit {
            sequence: feed.state_effect_floor + 1,
        })?;
        let error = feed.recv().await.unwrap_err();
        assert_eq!(
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .and_then(|error| error.reason()),
            Some("conversationResyncRequired")
        );
        assert!(
            feed.reader().ensure().is_err(),
            "uncovered State gap left the old read qualification active"
        );
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
