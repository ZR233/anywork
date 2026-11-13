//! Passive scoped completion delivery. One Set, monotonic Append prefixes, latest activity.
use super::{
    ConversationReader, StudioRuntime,
    conversation_reader::{
        JsonBudget, ReadResources, annotate_atoms, annotate_sources, core_demand, entries, query,
        resync,
    },
    thread_observation::ConversationSource,
};

use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::*;
use std::sync::Arc;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
pub enum ConversationEvent {
    Chat { batch: Box<ChatBatch> },
    Activity { snapshot: Arc<ActivitySnapshot> },
}
pub struct ConversationFeed {
    reader: ConversationReader,
    initial: Option<ChatBatch>,
    initial_activity: Option<Arc<ActivitySnapshot>>,
    progress: Option<watch::Receiver<Option<Arc<ConversationSource>>>>,
    target: Option<Arc<CompletionTarget>>,
    delivered: u64,
    seen_serial: u64,
    activity_revision: u64,
    demand: ReadDemand,
    cancel: CancellationToken,
}
/// A slow reader retains only a bounded observation head, never an obsolete
/// CurrentState's active bodies/collections.
struct CompletionTarget {
    serial: u64,
    session: core::Session,
    head: u64,
    activity: Arc<ActivitySnapshot>,
    sources: Arc<[ChatSourceState]>,
    effect: u64,
}
impl From<&ConversationSource> for CompletionTarget {
    fn from(source: &ConversationSource) -> Self {
        Self {
            serial: source.serial,
            session: source.session.clone(),
            head: source.head,
            activity: source.activity.clone(),
            sources: source.current.source_states().clone(),
            effect: source.current.projection().source_effect_seq,
        }
    }
}
impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationFeed")
            .field("reader", &self.reader)
            .field("delivered", &self.delivered)
            .finish_non_exhaustive()
    }
}
impl StudioRuntime {
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        scope: ChatScope,
        demand: ReadDemand,
    ) -> Result<ConversationFeed> {
        self.open_feed_resources(thread_id, scope, demand, true)
            .await
    }
    pub(super) async fn open_feed_resources(
        &self,
        thread_id: &str,
        scope: ChatScope,
        demand: ReadDemand,
        completed: bool,
    ) -> Result<ConversationFeed> {
        core_demand(demand)?;
        let scope_query = query(&scope)?;
        let id = crate::studio::ids::new_id("conversation");
        let slot = self.thread_observations.observation_slot(thread_id);
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let conversation = self
            .store
            .conversation_store(thread_id)
            .await?
            .open_reader();
        let history = self.store.history(thread_id).await?;
        conversation.wait_initialization().await?;
        if conversation.current_conversation().is_none() {
            history.prepare_conversation_read().await?;
        }
        let progress_rx = conversation.subscribe_progress();
        let cut = conversation
            .capture(crate::studio::conversation_store::ReadRequest::Current)
            .await?;
        let progress = Some(progress_rx);
        let mut initial_activity = Arc::new(ActivitySnapshot {
            revision: 0,
            completed_through: 0,
            execution_present: false,
            entries: Vec::new(),
        });
        let mut initial_serial = 0;
        let mut source_states = Vec::new();
        let mut cold_sources = None;
        let (session, database_id, head, effect_cut, items, boundary) =
            if let crate::studio::conversation_store::ReadCut::Ready { source, .. } = cut {
                let database_id = history
                    .conversation_database_id()
                    .await?
                    .ok_or_else(resync)?;
                let budget = JsonBudget::new(
                    database_id.clone(),
                    continuation_reserve(
                        &id,
                        &scope,
                        &database_id,
                        source.session.epoch().as_str(),
                    ),
                )
                .for_scope(&scope);
                validate_run(&scope, &database_id, &source.session, source.head, &budget).await?;
                let page = if completed {
                    Some(
                        source
                            .session
                            .page(
                                core::ChatPageRequest {
                                    query: scope_query,
                                    demand: core_demand(demand)?,
                                    before: None,
                                    ceiling: Some(source.head),
                                },
                                &budget,
                            )
                            .await?,
                    )
                } else {
                    None
                };
                initial_serial = source.serial;
                initial_activity = source.activity.clone();
                if completed {
                    source_states = source.current.source_states().to_vec();
                }
                let effect_cut = source.current.projection().source_effect_seq;
                let (items, boundary) = page.map_or_else(
                    || (Vec::new(), None),
                    |page| (page.items, page.before.map(|cursor| cursor.append_seq)),
                );
                (
                    source.session.clone(),
                    Some(database_id),
                    source.head,
                    effect_cut,
                    items,
                    boundary,
                )
            } else {
                let crate::studio::conversation_store::ReadCut::Cold(snapshot) = cut else {
                    unreachable!("handled ready cut")
                };
                let database_id = snapshot
                    .as_ref()
                    .map(|snapshot| snapshot.database_id.clone());
                let session = conversation.session().clone();
                let budget = JsonBudget::new(
                    database_id.clone().unwrap_or_default(),
                    continuation_reserve(
                        &id,
                        &scope,
                        database_id.as_deref().unwrap_or_default(),
                        session.epoch().as_str(),
                    ),
                )
                .for_scope(&scope);
                // The existing cold facade reads actual business state without installing execution.
                let cold = match snapshot {
                    Some(snapshot) if completed => {
                        snapshot
                            .cold_conversation(scope_query, core_demand(demand)?, &budget)
                            .await?
                    }
                    Some(snapshot) => Some(snapshot.presentation_baseline().await?),
                    None => None,
                };
                match cold {
                    Some(cold) => {
                        ensure!(
                            database_id.as_deref() == Some(cold.database_id.as_str()),
                            resync()
                        );
                        // Initialize the original Session's D/H from its read-only publication seed.
                        if completed {
                            session
                                .completed_after(
                                    core::ChatCompletionCursor::new(session.epoch(), 0),
                                    None,
                                    Some(0),
                                    core::ReadDemand::new(1, CHAT_BATCH_MAX_BYTES as usize),
                                    &budget,
                                )
                                .await?;
                        }
                        validate_run(&scope, &cold.database_id, &session, cold.head, &budget)
                            .await?;
                        let boundary = if cold.page.exhausted {
                            None
                        } else {
                            cold.page.items.first().map(|item| {
                                if matches!(scope, ChatScope::Main) {
                                    item.header
                                        .run
                                        .map_or(item.header.append_seq, |run| run.start_seq)
                                } else {
                                    item.header.append_seq
                                }
                            })
                        };
                        initial_activity = Arc::new(ActivitySnapshot {
                            completed_through: cold.head,
                            revision: 0,
                            execution_present: false,
                            entries: Vec::new(),
                        });
                        cold_sources = Some(cold.sources);
                        (
                            session,
                            Some(cold.database_id),
                            cold.head,
                            cold.current.source_effect_seq,
                            cold.page.items,
                            boundary,
                        )
                    }
                    None => {
                        ensure!(
                            !matches!(scope, ChatScope::Run { .. }),
                            core::ChatError::InvalidArgument("unknown completion run".into())
                        );
                        (session, None, 0, 0, Vec::new(), None)
                    }
                }
            };
        let mut initial_entries = entries(items, database_id.as_deref().unwrap_or_default())?;
        if !completed {
            // The presentation facade shares read resources, never reads/annotates an
            // atomic completion page as an intermediate representation.
        } else if let Some(sources) = cold_sources {
            annotate_atoms(&mut initial_entries, &sources)?;
        } else {
            annotate_sources(&mut initial_entries, &history, &source_states, effect_cut).await?;
        }
        conversation.bind_database(database_id.as_deref())?;
        let reader = ConversationReader::new(
            id,
            scope,
            head,
            effect_cut,
            slot,
            self.thread_observations.read_lifetime(),
            ReadResources {
                history,
                session,
                database_id,
                conversation,
                thread: thread.clone(),
                recovery: self.recovery.clone(),
            },
        );
        let initial = if completed {
            Some(reader.finish_batch(
                ChatBatch {
                    placement: ChatPlacement::Set,
                    entries: initial_entries,
                    before: reader.before(boundary).await?,
                    from_seq: None,
                    through_seq: head,
                },
                demand,
            )?)
        } else {
            None
        };
        let feed = ConversationFeed {
            reader,
            initial,
            initial_activity: completed.then_some(initial_activity),
            progress,
            target: None,
            delivered: head,
            seen_serial: initial_serial,
            activity_revision: 0,
            demand,
            cancel: CancellationToken::new(),
        };
        feed.reader.ensure()?;
        Ok(feed)
    }
}
async fn validate_run(
    scope: &ChatScope,
    database_id: &str,
    session: &core::Session,
    head: u64,
    budget: &JsonBudget,
) -> Result<()> {
    let ChatScope::Run { reference } = scope else {
        return Ok(());
    };
    ensure!(
        reference.database_id == database_id,
        core::ChatError::StaleContent
    );
    ensure!(
        reference.index_version == COMPLETED_READ_INDEX_VERSION
            && reference.start_seq > 0
            && reference.start_seq <= head,
        core::ChatError::InvalidArgument("invalid completion run reference".into())
    );
    let headers = JsonBudget::new(budget.database_id.clone(), String::new()).headers_only();
    let page = session
        .page(
            core::ChatPageRequest {
                query: query(scope)?,
                demand: core::ReadDemand::new(1, CHAT_BATCH_MAX_BYTES as usize),
                before: None,
                ceiling: Some(reference.start_seq),
            },
            &headers,
        )
        .await?;
    ensure!(
        page.items.len() == 1
            && page.items[0].header.append_seq == reference.start_seq
            && page.items[0]
                .header
                .run
                .is_some_and(|run| run.start_seq == reference.start_seq && run.ordinal == 1),
        core::ChatError::InvalidArgument("unknown completion run start".into())
    );
    Ok(())
}
fn continuation_reserve(lease: &str, scope: &ChatScope, database: &str, epoch: &str) -> String {
    serde_json::json!({"version":2,
        "index_version":COMPLETED_READ_INDEX_VERSION,"thread_id":lease,"lease":lease,"database":database,
        "scope":scope,"epoch":epoch,"ceiling":u64::MAX,"kind":{"kind":"Before","boundary":u64::MAX}}).to_string()
}
impl ConversationFeed {
    pub fn thread_id(&self) -> &str {
        self.reader.thread_id()
    }
    pub fn subscription_id(&self) -> &str {
        self.reader.subscription_id()
    }
    pub fn reader(&self) -> &ConversationReader {
        &self.reader
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
    }
    pub fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub(super) fn current_progress(&mut self) -> Option<Arc<ConversationSource>> {
        self.progress
            .as_mut()
            .and_then(|progress| progress.borrow_and_update().clone())
    }
    pub async fn close(&mut self) -> Result<()> {
        self.finish_production();
        Ok(())
    }
    pub(super) fn finish_production(&mut self) {
        self.cancel.cancel();
        self.progress = None;
        self.target = None;
        self.initial = None;
        self.initial_activity = None;
    }
    pub async fn recv(&mut self) -> Result<Option<ConversationEvent>> {
        let result = self.receive().await;
        if result.as_ref().err().is_some_and(|error| {
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .is_some_and(|error| error.reason() == Some("conversationResyncRequired"))
        }) {
            self.reader.invalidate();
        }
        if result.is_err() {
            self.finish_production();
        }
        result
    }
    fn take_progress(&mut self) -> Result<bool> {
        if self.target.is_some() {
            return Ok(true);
        }
        let Some(progress) = self.progress.as_mut() else {
            return Ok(false);
        };
        let newest = progress.borrow_and_update().clone();
        if let Some(newest) = newest
            && newest.serial > self.seen_serial
        {
            ensure!(newest.head >= self.delivered, resync());
            self.target = Some(Arc::new(CompletionTarget::from(newest.as_ref())));
            return Ok(true);
        }
        Ok(false)
    }
    async fn receive(&mut self) -> Result<Option<ConversationEvent>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(core::ChatError::Cancelled.into());
            }
            self.reader.ensure()?;
            if let Some(batch) = self.initial.take() {
                return Ok(Some(ConversationEvent::Chat {
                    batch: Box::new(batch),
                }));
            }
            if let Some(snapshot) = self.initial_activity.take() {
                ensure!(snapshot.completed_through == self.delivered, resync());
                self.activity_revision = snapshot.revision;
                return Ok(Some(ConversationEvent::Activity { snapshot }));
            }
            self.take_progress()?;
            if let Some(target) = self.target.clone() {
                if target.head > self.delivered {
                    let mut replay_query = query(&self.reader.inner.scope)?;
                    if matches!(self.reader.inner.scope, ChatScope::Main) {
                        replay_query.selection = core::ChatSelection::Records;
                    }
                    let budget = self
                        .reader
                        .budget()
                        .await?
                        .for_scope(&self.reader.inner.scope);
                    let batch = target
                        .session
                        .completed_after(
                            core::ChatCompletionCursor::new(target.session.epoch(), self.delivered),
                            Some(replay_query),
                            Some(target.head),
                            core_demand(self.demand)?,
                            &budget,
                        )
                        .await?;
                    ensure!(
                        batch.through_seq > self.delivered && batch.through_seq <= target.head,
                        resync()
                    );
                    let mut product = ChatBatch {
                        placement: ChatPlacement::Append,
                        entries: entries(batch.items, &budget.database_id)?,
                        before: None,
                        from_seq: Some(self.delivered),
                        through_seq: batch.through_seq,
                    };
                    if matches!(self.reader.inner.scope, ChatScope::Main) {
                        product
                            .entries
                            .retain(|entry| entry.main_presentation != MainPresentation::Hidden);
                    }
                    self.reader
                        .annotate_source_states(
                            &mut product.entries,
                            &target.sources,
                            target.effect,
                        )
                        .await?;
                    let product = self.reader.finish_batch(product, self.demand)?;
                    self.delivered = product.through_seq;
                    // Empty Appends still accept filtered completion progress and unblock Activity.
                    return Ok(Some(ConversationEvent::Chat {
                        batch: Box::new(product),
                    }));
                }
                self.target = None;
                self.seen_serial = target.serial;
                if target.activity.completed_through < self.delivered
                    || target.activity.revision <= self.activity_revision
                {
                    continue;
                }
                ensure!(
                    target.activity.completed_through == self.delivered,
                    resync()
                );
                self.activity_revision = target.activity.revision;
                return Ok(Some(ConversationEvent::Activity {
                    snapshot: target.activity.clone(),
                }));
            }
            self.wait_change().await?;
        }
    }
    pub(super) async fn wait_change(&mut self) -> Result<()> {
        let progress_open = tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(core::ChatError::Cancelled.into()),
            progress = async { match self.progress.as_mut() { Some(progress) => progress.changed().await.is_ok(), None => std::future::pending().await } } => progress,
        };
        ensure!(progress_open, resync());
        Ok(())
    }
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    use crate::studio::ConversationStateFeed;
    use anyhow::{Context, Result, bail};
    use pl_core::chat::ChatKey;
    use pl_provider_fixture::{Protocol, Reply, ReplyStage, RequestMatch, Step};
    use std::{collections::HashMap, time::Duration};

    use crate::runtime_test_support as support;

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

        async fn execute(
            &self,
            _args: EchoArgs,
            (): (),
        ) -> Result<FailSerializeOutput, Self::Error> {
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
                    ConversationEvent::Activity { .. } => {}
                }
            }
        })
        .await?
    }
    pub(in crate::studio::runtime) fn demand() -> ReadDemand {
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

    async fn initial_snapshot(state: &mut ConversationStateFeed) -> Result<ThreadSnapshot> {
        let update = state.recv().await?.context("missing initial State")?;
        let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = update else {
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
        state: &mut ConversationStateFeed,
        interaction_id: &str,
        pending_revision: u64,
        mut revision: u64,
        pending: &mut usize,
        resolved: &mut usize,
    ) -> Result<()> {
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let update = state
                    .recv()
                    .await?
                    .context("state feed ended before terminal State")?;
                let ThreadSubscriptionUpdate::Notification { notification } = update else {
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
                    ThreadNotification::TurnCompleted { .. } if *resolved == 1 => return Ok(()),
                    _ => {}
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
    async fn question_cut_late_open_starts_with_published_pending_and_delivers_one_answer()
    -> Result<()> {
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
            let mut state = env.runtime.open_conversation_state_feed(id).await?;
            let snapshot = initial_snapshot(&mut state).await?;
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
                &mut state,
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
            state.close().await?;
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
            let mut state = env.runtime.open_conversation_state_feed(id).await?;
            let snapshot = initial_snapshot(&mut state).await?;
            assert!(
                snapshot.interactions.is_empty(),
                "held tool interaction entered the initial cut"
            );
            stage.release();

            let mut state_revision = snapshot.revision;
            let pending = tokio::time::timeout(Duration::from_secs(20), async {
                loop {
                    let update = state
                        .recv()
                        .await?
                        .context("state feed ended before pending question")?;
                    let ThreadSubscriptionUpdate::Notification { notification } = update else {
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
                &mut state,
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
            state.close().await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        stage.release();
        env.finish(result).await
    }

    pub(in crate::studio::runtime) async fn state_snapshot(
        state: &mut ConversationStateFeed,
    ) -> Result<Box<ThreadSnapshot>> {
        let update = state.recv().await?.context("missing State baseline")?;
        let ThreadSubscriptionUpdate::Snapshot { snapshot, .. } = update else {
            bail!("first State must be a snapshot");
        };
        Ok(snapshot)
    }

    #[tokio::test]
    async fn terminal_publication_precedes_immediate_directory_and_one_shot_reads() -> Result<()> {
        for realtime in [true, false] {
            let stage = ReplyStage::new();
            let env = support::Environment::new(
                vec![support::prompt_step(
                    "terminal-directory-order",
                    0,
                    support::held_reply(&stage, "terminal-directory-response"),
                )],
                vec![],
            )
            .await?;
            let result = async {
                let started = env
                    .start(ThreadWorkspaceMode::Local, "terminal-directory-order")
                    .await?;
                let id = &started.thread.id;
                support::reached(&stage).await?;
                let mut state = if realtime {
                    let mut state = env.runtime.open_conversation_state_feed(id).await?;
                    let _baseline = state_snapshot(&mut state).await?;
                    Some(state)
                } else {
                    None
                };
                let feed = env
                    .runtime
                    .thread_observations
                    .live_feed(id)
                    .context("installed product observation owner")?;
                let mut retained = feed.last_turn();
                assert!(retained.borrow().is_none());
                stage.release();
                let terminal = tokio::time::timeout(Duration::from_secs(20), async {
                    if let Some(state) = state.as_mut() {
                        while let Some(update) = state.recv().await? {
                            if let ThreadSubscriptionUpdate::Notification { notification } = update
                                && let ThreadNotification::TurnCompleted { turn } =
                                    notification.notification
                            {
                                return Ok::<_, anyhow::Error>(turn);
                            }
                        }
                        bail!("State closed before terminal publication");
                    }
                    // No State subscriber exists: wait on the production retained fact, not on
                    // durability or an owner sync that would hide the publication-order window.
                    retained.changed().await?;
                    Ok(retained
                        .borrow_and_update()
                        .clone()
                        .context("retained terminal")?
                        .as_ref()
                        .clone())
                })
                .await??;
                assert!(terminal.state.is_terminal());
                let directory = env.runtime.read_protocol_thread(id).await?;
                assert_eq!(directory.status, pl_protocol::ThreadStatus::Idle);
                let snapshot = env.runtime.thread_snapshot(id).await?;
                assert_eq!(snapshot.thread.status, pl_protocol::ThreadStatus::Idle);
                assert!(snapshot.active_turn.is_none());
                if let Some(state) = state.as_mut() {
                    state.close().await?;
                } else {
                    let mut reopened = env.runtime.open_conversation_state_feed(id).await?;
                    assert_eq!(
                        state_snapshot(&mut reopened).await?.thread.status,
                        pl_protocol::ThreadStatus::Idle
                    );
                    reopened.close().await?;
                }
                Ok(())
            }
            .await;
            stage.release();
            env.finish(result).await?;
        }
        Ok(())
    }

    fn configure_plan_feed(env: &support::Environment) -> Result<()> {
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
        Ok(())
    }

    async fn observe_pending_plan_feed(
        env: &support::Environment,
        stage: &ReplyStage,
    ) -> Result<(String, crate::InteractionRequest, String)> {
        let started = env
            .start(ThreadWorkspaceMode::Local, "pending-plan-feed")
            .await?;
        let id = &started.thread.id;
        support::reached(stage).await?;
        let mut live = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        let mut live_state = env.runtime.open_conversation_state_feed(id).await?;
        assert_eq!(chat(&mut live).await?.placement, ChatPlacement::Set);
        assert!(
            state_snapshot(&mut live_state)
                .await?
                .interactions
                .is_empty()
        );
        stage.release();
        let pending = tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(update) = live_state.recv().await? {
                if let ThreadSubscriptionUpdate::Notification { notification } = update
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
        live_state.close().await?;
        live.reader().close().await?;
        Ok((id.clone(), pending, completed.id))
    }

    async fn check_hot_plan_feed(
        env: &support::Environment,
        id: &str,
        pending: &crate::InteractionRequest,
        plan: &str,
    ) -> Result<()> {
        let mut reopened = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut reopened).await?.placement, ChatPlacement::Set);
        let mut reopened_state = env.runtime.open_conversation_state_feed(id).await?;
        let baseline = state_snapshot(&mut reopened_state).await?;
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
        reopened_state.close().await?;
        reopened.reader().close().await?;
        Ok(())
    }

    async fn check_cold_plan_feed(
        env: &mut support::Environment,
        id: &str,
        pending: &crate::InteractionRequest,
        plan: &str,
    ) -> Result<()> {
        env.restart().await?;
        let saved = env
            .runtime
            .store
            .history(id)
            .await?
            .checkpoint()
            .await?
            .context("normal shutdown checkpoint")?;
        assert_eq!(
            saved.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed,
            "this journey must restore a normally shut down Core resource"
        );
        let directory = env.runtime.read_protocol_thread(id).await?;
        assert_eq!(directory.status, pl_protocol::ThreadStatus::Idle);
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
        let mut cold_state = env.runtime.open_conversation_state_feed(id).await?;
        let baseline = state_snapshot(&mut cold_state).await?;
        assert_eq!(baseline.thread.status, directory.status);
        let point_in_time = env.runtime.thread_snapshot(id).await?;
        assert_eq!(point_in_time.thread.status, directory.status);
        assert_eq!(point_in_time.interactions, vec![pending.clone()]);
        assert_eq!(point_in_time.business_refs, baseline.business_refs);
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
        cold_state.close().await?;
        cold.reader().close().await?;
        Ok(())
    }

    async fn approve_plan_feed(
        env: &support::Environment,
        id: &str,
        pending: crate::InteractionRequest,
        completed_id: &str,
    ) -> Result<()> {
        let mut continuation = env.runtime.open_conversation_state_feed(id).await?;
        let resolved = env
            .runtime
            .resolve_interaction(
                "approve-feed-plan".into(),
                id.to_owned(),
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
        // The answer command, not observation, activates execution. That installs
        // a new source and intentionally invalidates the old cold qualification.
        let error = continuation.recv().await.unwrap_err();
        assert_eq!(
            error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .and_then(|error| error.reason()),
            Some("conversationResyncRequired")
        );
        continuation.close().await?;
        let mut continuation = env.runtime.open_conversation_state_feed(id).await?;
        tokio::time::timeout(Duration::from_secs(20), async {
            while let Some(update) = continuation.recv().await? {
                if let ThreadSubscriptionUpdate::Notification { notification } = update
                    && let ThreadNotification::TurnCompleted { turn } = notification.notification
                    && turn.id != completed_id
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
        continuation.close().await?;
        assert_eq!(env.root_provider.recorded().len(), 2);
        let mut approved = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut approved).await?.placement, ChatPlacement::Set);
        let mut approved_state = env.runtime.open_conversation_state_feed(id).await?;
        assert!(
            state_snapshot(&mut approved_state)
                .await?
                .interactions
                .is_empty(),
            "answered Plan returned as pending"
        );
        approved.close().await?;
        approved_state.close().await?;
        approved.reader().close().await?;
        Ok(())
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
            configure_plan_feed(&env)?;
            env.restart().await?;
            let (id, pending, completed_id) = observe_pending_plan_feed(&env, &stage).await?;
            check_hot_plan_feed(&env, &id, &pending, &plan).await?;
            check_cold_plan_feed(&mut env, &id, &pending, &plan).await?;
            approve_plan_feed(&env, &id, pending, &completed_id).await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        stage.release();
        env.finish(result).await
    }

    mod allocation {
        //! Test-only allocation requests made while polling the real feed receive future.
        //!
        //! This is gross requested volume (including successful realloc's new size),
        //! not resident memory, physical IO, or an exact serialization count. Other
        //! tasks polled later, or work dispatched to another thread, are outside a poll.
        use std::{
            alloc::{GlobalAlloc, Layout, System},
            cell::Cell,
            future::{Future, poll_fn},
        };

        #[derive(Clone, Copy, Debug, Default)]
        pub(super) struct Sample {
            pub bytes: usize,
            overflow: bool,
            unavailable: bool,
        }

        impl Sample {
            fn record(&mut self, bytes: usize) {
                match self.bytes.checked_add(bytes) {
                    Some(total) => self.bytes = total,
                    None => {
                        self.bytes = usize::MAX;
                        self.overflow = true;
                    }
                }
            }

            pub(super) fn add(&mut self, sample: Self) {
                self.record(sample.bytes);
                self.overflow |= sample.overflow;
                self.unavailable |= sample.unavailable;
            }

            pub(super) fn validate(self) -> anyhow::Result<Self> {
                // Run only after leaving the observer, never inside an allocator method.
                anyhow::ensure!(!self.overflow, "allocation request byte counter overflowed");
                anyhow::ensure!(!self.unavailable, "allocation observer TLS is unavailable");
                Ok(self)
            }
        }

        #[derive(Clone, Copy, Default)]
        struct Observer {
            enabled: bool,
            sample: Sample,
        }

        std::thread_local! {
            // Const initialization and scalar Cell operations require no allocator.
            // try_with also permits ordinary allocations during thread-local teardown.
            static OBSERVER: Cell<Observer> = const {
                Cell::new(Observer {
                    enabled: false,
                    sample: Sample { bytes: 0, overflow: false, unavailable: false },
                })
            };
        }

        fn record(bytes: usize) {
            let _ = OBSERVER.try_with(|slot| {
                let mut observer = slot.get();
                if observer.enabled {
                    observer.sample.record(bytes);
                    slot.set(observer);
                }
            });
        }

        struct ObservedSystem;

        #[global_allocator]
        static ALLOCATOR: ObservedSystem = ObservedSystem;

        // SAFETY: All four operations delegate to System with the caller's unchanged
        // pointer, Layout and new size; returned pointers/nulls are returned unchanged.
        // Every allocation handled here therefore has the same System provenance on
        // deallocation/reallocation. The observer never accesses allocated memory,
        // changes allocation failures, or frees anything. Its only operations are
        // try_with, scalar Cell reads/writes and checked integer arithmetic: no locks,
        // formatting, allocation, assertions, or unwinding inside allocator callbacks.
        unsafe impl GlobalAlloc for ObservedSystem {
            unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
                // SAFETY: GlobalAlloc's caller supplies the valid nonzero Layout.
                let pointer = unsafe { System.alloc(layout) };
                if !pointer.is_null() {
                    record(layout.size());
                }
                pointer
            }

            unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
                // SAFETY: Preserve the caller's Layout and System's zeroing contract.
                let pointer = unsafe { System.alloc_zeroed(layout) };
                if !pointer.is_null() {
                    record(layout.size());
                }
                pointer
            }

            unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
                // SAFETY: The caller supplies a live allocation and its original Layout.
                // All allocations above came from System, including outside a sample.
                unsafe { System.dealloc(pointer, layout) };
            }

            unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
                // SAFETY: Preserve the live System allocation, old Layout and valid new
                // size. System alone moves/releases it; null leaves the old block live.
                let next = unsafe { System.realloc(pointer, layout, new_size) };
                if !next.is_null() {
                    record(new_size);
                }
                next
            }
        }

        struct PollScope {
            previous: Observer,
            active: bool,
        }

        impl PollScope {
            fn enter() -> anyhow::Result<Self> {
                let previous = OBSERVER
                    .try_with(|slot| {
                        slot.replace(Observer {
                            enabled: true,
                            sample: Sample::default(),
                        })
                    })
                    .map_err(|_| anyhow::anyhow!("allocation observer TLS is unavailable"))?;
                Ok(Self {
                    previous,
                    active: true,
                })
            }

            fn restore(&mut self) -> Option<Sample> {
                if !self.active {
                    return None;
                }
                self.active = false;
                OBSERVER
                    .try_with(|slot| {
                        let sample = slot.get().sample;
                        let mut previous = self.previous;
                        if previous.enabled {
                            previous.sample.add(sample);
                        }
                        slot.set(previous);
                        sample
                    })
                    .ok()
            }

            fn finish(mut self) -> Sample {
                self.restore().unwrap_or(Sample {
                    unavailable: true,
                    ..Sample::default()
                })
            }
        }

        impl Drop for PollScope {
            fn drop(&mut self) {
                // Also restores a previously enabled outer scope if the future panics.
                // No fallible reporting or unwinding is allowed in this cleanup.
                let _ = self.restore();
            }
        }

        pub(super) async fn measure<F: Future>(future: F) -> anyhow::Result<(F::Output, Sample)> {
            // Pinning/setup and all assertion/serialization work stay outside the scope.
            let mut future = Box::pin(future);
            let mut total = Sample::default();
            let output = poll_fn(|context| {
                let scope = match PollScope::enter() {
                    Ok(scope) => scope,
                    Err(error) => return std::task::Poll::Ready(Err(error)),
                };
                let result = future.as_mut().poll(context);
                total.add(scope.finish());
                result.map(Ok)
            })
            .await?;
            Ok((output, total.validate()?))
        }

        #[test]
        fn observation_scope_restores_after_pending_unwind_and_nested_poll() {
            use std::{panic::AssertUnwindSafe, task::Context};
            let waker = futures::task::noop_waker();
            let mut context = Context::from_waker(&waker);
            let enabled = || OBSERVER.with(|slot| slot.get().enabled);

            let mut pending = Box::pin(measure(std::future::pending::<()>()));
            assert!(pending.as_mut().poll(&mut context).is_pending());
            assert!(!enabled());

            let outer = PollScope::enter().unwrap();
            assert!(pending.as_mut().poll(&mut context).is_pending());
            assert!(enabled(), "nested poll lost its outer observation scope");
            drop(outer);
            assert!(!enabled());

            let mut panicking = Box::pin(measure(async { panic!("poll unwind fixture") }));
            let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
                panicking.as_mut().poll(&mut context)
            }));
            assert!(result.is_err());
            assert!(!enabled(), "unwinding left allocation observation enabled");
        }
    }

    pub(in crate::studio::runtime) mod completed_runs {
        use super::*;
        use crate::studio::thread_projection::{LiveProjection, PreparedEffect};
        use pl_core::{
            context::OpaquePayload,
            model::{
                ModelCompletedMember, ModelContentAvailableMember, ModelStartedMember,
                ModelTextChannel, ObservedItemKind, ObservedPartIdentity, ObservedPartKind,
                ProviderPartIdentity,
            },
            thread::{
                ThreadEffectBatch, ThreadSnapshot as CoreSnapshot, TurnRecord,
                TurnState as CoreTurnState,
            },
        };
        use pl_model::{
            completion::{
                CompletionPresentationItem, CompletionPresentationItemKind,
                CompletionPresentationPart, CompletionPresentationPartKind,
            },
            runtime::{ModelMemberReceipt, ModelMemberState},
        };

        pub(in crate::studio::runtime) fn start(id: &str, reasoning: bool) -> ModelStartedMember {
            ModelStartedMember {
                turn_id: "atomic-turn".into(),
                attempt_id: "atomic-attempt".into(),
                generation: 0,
                identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
                    item_id: id.into(),
                    output_index: None,
                    content_index: 0,
                    item_kind: if reasoning {
                        ObservedItemKind::Reasoning
                    } else {
                        ObservedItemKind::Text(ModelTextChannel::Final)
                    },
                    part: if reasoning {
                        ObservedPartKind::ReasoningText
                    } else {
                        ObservedPartKind::OutputText
                    },
                }),
            }
        }

        pub(in crate::studio::runtime) fn finish(
            id: &str,
            reasoning: bool,
            text: &str,
        ) -> Result<ModelCompletedMember> {
            let receipt = ModelMemberReceipt {
                item: CompletionPresentationItem {
                    provider_item_id: id.into(),
                    output_index: None,
                    kind: if reasoning {
                        CompletionPresentationItemKind::Reasoning
                    } else {
                        CompletionPresentationItemKind::Text(
                            pl_protocol::trace::TraceTextChannel::Final,
                        )
                    },
                    parts: vec![CompletionPresentationPart {
                        content_index: 0,
                        provider_part_id: None,
                        text: text.into(),
                        kind: if reasoning {
                            CompletionPresentationPartKind::ReasoningText
                        } else {
                            CompletionPresentationPartKind::OutputText
                        },
                    }],
                },
                state: ModelMemberState::Completed,
            };
            Ok(ModelCompletedMember {
                turn_id: "atomic-turn".into(),
                attempt_id: "atomic-attempt".into(),
                generation: 0,
                member_id: id.into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            })
        }

        pub(in crate::studio::runtime) fn publish(
            source: &super::super::super::thread_observation::ThreadLiveFeed,
            session: &core::Session,
            prepared: &Arc<PreparedEffect>,
        ) -> Result<()> {
            source.publish_test_conversation(
                session,
                prepared.current_state.clone().context("prepared current")?,
            )
        }

        pub(in crate::studio::runtime) struct Harness {
            pub thread: Thread,
            pub history: crate::studio::storage::history::HistoryStore,
            pub session: core::Session,
            pub projection: LiveProjection,
            pub source: Arc<super::super::super::thread_observation::ThreadLiveFeed>,
            pub conversation: Arc<crate::studio::conversation_store::ConversationStore>,
            pub sequence: u64,
            _owner: watch::Sender<super::super::super::thread_observation::Progress>,
        }
        impl Harness {
            pub async fn new(env: &support::Environment) -> Result<Self> {
                let (delta, directory_session, agent) =
                    crate::studio::store::directory::DirectoryDelta::register_session(
                        crate::studio::ids::new_id("timeline-fixture"),
                        &env.project.id,
                        "timeline fixture",
                        ThreadModeId::simple(),
                        ThreadWorkspaceMode::Local,
                        env.project.path.clone(),
                        crate::config::ROOT_AGENT_ROUTE_KEY,
                    );
                let thread =
                    crate::studio::records::thread_projection(&directory_session, &agent, |id| {
                        (id == agent.agent_id).then(|| agent.thread_id.clone())
                    })?;
                env.runtime
                    .agent_facility
                    .product_events
                    .commit_directory(delta)
                    .await?;
                assert!(
                    env.runtime
                        .session_of(&thread.id)
                        .and_then(|session| session.observed_thread(&thread.id))
                        .is_none()
                );
                let history = env.runtime.store.history(&thread.id).await?;
                history.prepare_write().await?;
                let database = history
                    .conversation_database_id()
                    .await?
                    .context("database")?;
                let conversation = env.runtime.store.conversation_store(&thread.id).await?;
                let session = conversation.session().clone();
                let channel = env
                    .runtime
                    .store
                    .thread_persistence()
                    .history_channel(&thread.id);
                let mut projection = LiveProjection::new();
                projection.bind_execution_history(channel.order_index(), history.clone())?;
                projection.bind_conversation_identity(database)?;
                projection.observe_test_current(&thread, Vec::new())?;
                let (owner, progress) = watch::channel(Default::default());
                let source = Arc::new(
                    super::super::super::thread_observation::ThreadLiveFeed::new(
                        None,
                        progress,
                        Default::default(),
                    ),
                );
                source.bind_conversation(&conversation);
                source.bind_test_presentation(projection.presentation());
                env.runtime
                    .thread_observations
                    .observation_slot(&thread.id)
                    .install(source.clone());
                source.publish_test_conversation(
                    &session,
                    projection.current_state().context("initial")?,
                )?;
                Ok(Self {
                    thread,
                    history,
                    session,
                    projection,
                    source,
                    conversation,
                    sequence: 0,
                    _owner: owner,
                })
            }
            pub async fn effect(
                &mut self,
                starts: Vec<ModelStartedMember>,
                members: Vec<ModelCompletedMember>,
            ) -> Result<Arc<PreparedEffect>> {
                self.effect_phases(starts, vec![], members, CoreTurnState::Running)
                    .await
            }
            pub async fn content_available(
                &mut self,
                starts: Vec<ModelStartedMember>,
            ) -> Result<Arc<PreparedEffect>> {
                self.effect_phases(
                    vec![],
                    starts
                        .into_iter()
                        .map(|start| ModelContentAvailableMember {
                            turn_id: start.turn_id,
                            attempt_id: start.attempt_id,
                            generation: start.generation,
                            identity: start.identity,
                        })
                        .collect(),
                    vec![],
                    CoreTurnState::Running,
                )
                .await
            }
            pub async fn finish_successfully(&mut self) -> Result<Arc<PreparedEffect>> {
                self.effect_phases(
                    vec![],
                    vec![],
                    vec![],
                    CoreTurnState::Finished(pl_core::thread::TurnOutcome::Completed),
                )
                .await
            }
            async fn effect_phases(
                &mut self,
                starts: Vec<ModelStartedMember>,
                visible: Vec<ModelContentAvailableMember>,
                members: Vec<ModelCompletedMember>,
                turn_state: CoreTurnState,
            ) -> Result<Arc<PreparedEffect>> {
                self.sequence += 1;
                let turn = TurnRecord {
                    elapsed_ms: None,
                    input_id: None,
                    turn_id: "atomic-turn".into(),
                    state: turn_state.clone(),
                    model_steps: 1,
                };
                let state = CoreSnapshot {
                    turns: vec![turn.clone()].into(),
                    attempts: if matches!(turn_state, CoreTurnState::Running) {
                        vec![pl_core::thread::RequestAttempt::new(
                            "atomic-turn".into(),
                            "atomic-attempt".into(),
                            0,
                            pl_core::thread::AttemptStatus::Running,
                        )]
                    } else {
                        vec![]
                    }
                    .into(),
                    ..Default::default()
                };
                let effect = ThreadEffectBatch {
                    thread_id: self.thread.id.clone(),
                    sequence: self.sequence,
                    committed_at: self.sequence as i64 + 10,
                    turn: Some(turn),
                    model_member_starts: starts.into(),
                    model_member_content_available: visible,
                    model_members: members.into(),
                    ..Default::default()
                };
                let (_, mut prepared) = self
                    .projection
                    .prepare(&self.thread, &effect, &state, false)
                    .await?;
                self.projection
                    .publish_prepared(&self.session, &mut prepared)
                    .await?;
                publish(&self.source, &self.session, &prepared)?;
                Ok(prepared)
            }
            pub async fn save(&self, prepared: &PreparedEffect) -> Result<()> {
                save_effect(&self.history, &self.session, prepared).await
            }
            pub(in crate::studio::runtime) async fn background_result(
                &mut self,
                index: u64,
            ) -> Result<Arc<PreparedEffect>> {
                self.prepare_background_result(index, true).await
            }
            async fn prepare_background_result(
                &mut self,
                index: u64,
                publish_cut: bool,
            ) -> Result<Arc<PreparedEffect>> {
                self.prepare_background_result_and_text(index, publish_cut, false, false)
                    .await
            }
            async fn prepare_background_result_and_text(
                &mut self,
                index: u64,
                publish_cut: bool,
                separator: bool,
                launch: bool,
            ) -> Result<Arc<PreparedEffect>> {
                use pl_core::{
                    context::{
                        AgentMessageKind, ContextContent, ContextRecord, ContextSnapshot,
                        ContextSource,
                    },
                    model::ModelToolCall,
                    thread::{
                        ToolDelivery, ToolOutcome,
                        inbox::{InboxRecord, ThreadMessage},
                        task::{TaskAcknowledgement, TaskRecord, TaskStatus},
                    },
                };
                self.sequence += 1;
                let call = format!("background-call-{index}");
                let turn = format!("origin-turn-{index}");
                let payload = OpaquePayload::text(format!("result-{index}"));
                let task = TaskRecord {
                    parent_call_id: None,
                    invocation: None,
                    id: format!("background-task-{index}"),
                    call_id: call.clone(),
                    tool_id: "exec".into(),
                    turn_id: turn.clone(),
                    revision: if launch { 1 } else { 2 },
                    status: if launch {
                        TaskStatus::Running
                    } else {
                        TaskStatus::Succeeded
                    },
                    cancel_requested: false,
                    acknowledgement: Some(TaskAcknowledgement {
                        record_id: format!("ack-{index}"),
                        context_revision: 1,
                    }),
                    started_sequence: Some(if separator {
                        self.sequence - 1
                    } else {
                        self.sequence
                    }),
                };
                let delivery = ToolDelivery {
                    target: Default::default(),
                    call_id: call.clone(),
                    tool_id: "exec".into(),
                    output: pl_core::tool::ToolOutput::new(payload.clone(), vec![]),
                    delivered_context: vec![ContextContent::Text {
                        text: format!("result-{index}").into(),
                    }],
                    outcome: ToolOutcome::Succeeded,
                };
                let inbox = InboxRecord {
                    sequence: index,
                    message: ThreadMessage {
                        id: format!("result-message-{index}"),
                        source_id: task.id.clone(),
                        kind: AgentMessageKind::Report,
                        payload,
                        context: vec![],
                    },
                };
                let deliveries: Arc<[_]> = if launch { vec![] } else { vec![delivery] }.into();
                let inbox: Arc<[_]> = if launch { vec![] } else { vec![inbox] }.into();
                let state = CoreSnapshot {
                    context: ContextSnapshot {
                        revision: 1,
                        records: vec![ContextRecord {
                            id: format!("request-{index}"),
                            turn_id: Some(turn),
                            source: ContextSource::Assistant,
                            content: vec![],
                            tool_calls: vec![ModelToolCall {
                                call_id: call,
                                tool_id: "exec".into(),
                                arguments: OpaquePayload::text("{}"),
                                presentation_contract: None,
                                rejection: None,
                            }],
                        }]
                        .into(),
                    },
                    tasks: [(task.id.clone(), task.clone())].into_iter().collect(),
                    deliveries: deliveries.clone(),
                    inbox: inbox.clone(),
                    ..Default::default()
                };
                let effect = ThreadEffectBatch {
                    thread_id: self.thread.id.clone(),
                    sequence: self.sequence,
                    committed_at: self.sequence as i64 + 10,
                    context: launch.then(|| pl_core::thread::journal::ContextChange::Append {
                        revision: 1,
                        records: vec![ContextRecord {
                            id: format!("ack-{index}"),
                            turn_id: Some(task.turn_id.clone()),
                            source: ContextSource::ToolResult {
                                call_id: task.call_id.clone(),
                                tool_id: task.tool_id.clone(),
                            },
                            content: vec![ContextContent::Text {
                                text: "started in background".into(),
                            }],
                            tool_calls: Vec::new(),
                        }]
                        .into(),
                    }),
                    tasks: vec![task].into(),
                    deliveries,
                    inbox,
                    model_member_starts: if separator {
                        vec![start("separator", false)]
                    } else {
                        vec![]
                    }
                    .into(),
                    model_members: if separator {
                        vec![finish("separator", false, "visible separator")?]
                    } else {
                        vec![]
                    }
                    .into(),
                    model_member_content_available: if separator {
                        let start = start("separator", false);
                        vec![ModelContentAvailableMember {
                            turn_id: start.turn_id,
                            attempt_id: start.attempt_id,
                            generation: start.generation,
                            identity: start.identity,
                        }]
                    } else {
                        vec![]
                    },
                    ..Default::default()
                };
                let (_, mut prepared) = self
                    .projection
                    .prepare(&self.thread, &effect, &state, false)
                    .await?;
                self.projection
                    .publish_prepared(&self.session, &mut prepared)
                    .await?;
                if publish_cut {
                    publish(&self.source, &self.session, &prepared)?;
                }
                Ok(prepared)
            }
        }

        async fn save_effect(
            history: &crate::studio::storage::history::HistoryStore,
            session: &core::Session,
            prepared: &PreparedEffect,
        ) -> Result<()> {
            use crate::studio::storage::history::EffectCommit;
            history
                .commit_effect(
                    prepared.sequence,
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
                        attempt: None,
                    },
                )
                .await?;
            session.confirm_durable(
                prepared
                    .completions
                    .iter()
                    .map(|item| item.header.append_seq)
                    .max()
                    .unwrap_or(session.durable_seq()),
            )?;
            Ok(())
        }

        pub(super) async fn activity(feed: &mut ConversationFeed) -> Result<Arc<ActivitySnapshot>> {
            tokio::time::timeout(Duration::from_secs(20), async {
                match feed.recv().await?.context("activity feed ended")? {
                    ConversationEvent::Activity { snapshot } => Ok(snapshot),
                    ConversationEvent::Chat { .. } => {
                        bail!("Activity crossed an unaccepted completion batch")
                    }
                }
            })
            .await?
        }

        /// I01/I18: the real projection publishes B, text, A; no display closure or admission order.
        #[tokio::test]
        async fn completion_order_and_fixed_activity_target_survive_split_batches() -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                h.effect(
                    vec![start("A", true), start("B", true), start("text", false)],
                    vec![],
                )
                .await?;
                let mut feed = env
                    .runtime
                    .open_conversation_feed(
                        &h.thread.id,
                        ChatScope::Main,
                        ReadDemand {
                            max_items: 1,
                            ..demand()
                        },
                    )
                    .await?;
                let initial = chat(&mut feed).await?;
                assert!(initial.entries.is_empty());
                let old = activity(&mut feed).await?;
                assert_eq!(old.entries.len(), 3);
                let b = h
                    .effect(vec![], vec![finish("B", true, "B first")?])
                    .await?;
                let b_id = b.completions[0].header.item_id.clone();
                let text = h
                    .effect(vec![], vec![finish("text", false, "text second")?])
                    .await?;
                let text_id = text.completions[0].header.item_id.clone();
                // Freeze a single target with two completions, then publish A after its first frame.
                let first = chat(&mut feed).await?;
                assert_eq!(first.from_seq, Some(0));
                assert_eq!(first.through_seq, 1);
                assert_eq!(first.entries[0].record_id, b_id);
                assert!(matches!(
                    first.entries[0].atom.payload,
                    Some(PayloadData::Deferred { .. })
                ));
                let retired = crate::studio::thread_projection::completed_activity_identity(
                    &first.entries[0],
                );
                assert_eq!(
                    retired,
                    Some(ActivityIdentity::ModelPart {
                        atom_id: first.entries[0].atom.id.clone()
                    })
                );
                let a = h.effect(vec![], vec![finish("A", true, "A last")?]).await?;
                let second = chat(&mut feed).await?;
                assert_eq!((second.from_seq, second.through_seq), (Some(1), 2));
                assert_eq!(second.entries[0].record_id, text_id);
                let cut = activity(&mut feed).await?;
                assert_eq!(cut.completed_through, 2);
                assert!(cut.revision > old.revision);
                assert_eq!(cut.entries.len(), 1);
                assert!(
                    cut.entries
                        .iter()
                        .all(|entry| entry.identity != retired.clone().unwrap())
                );
                let third = chat(&mut feed).await?;
                assert_eq!((third.from_seq, third.through_seq), (Some(2), 3));
                assert_eq!(third.entries[0].record_id, a.completions[0].header.item_id);
                assert!(activity(&mut feed).await?.entries.is_empty());
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        /// I17/I19: a subscriber which never polls does not participate in completion or writer admission.
        #[tokio::test]
        async fn slow_observer_keeps_only_latest_activity_and_queries_do_not_need_stream_credit()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let mut feed = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                h.effect(vec![start("long", true)], vec![]).await?;
                let prepared = h
                    .effect(
                        vec![],
                        vec![finish("long", true, &"large body".repeat(5000))?],
                    )
                    .await?;
                h.save(&prepared).await?;
                // Pure activity updates never allocate completion sequences or write history.
                let head = h.session.head_seq();
                let state = h.source.subscribe();
                for _ in 0..1024 {
                    h.source.publish_test_conversation(
                        &h.session,
                        h.projection.current_state().context("current")?,
                    )?;
                }
                assert_eq!(h.session.head_seq(), head);
                assert_eq!(h.session.durable_seq(), head);
                assert_eq!(
                    state.len(),
                    0,
                    "token/current-only publications must not emit BusinessRefsChanged"
                );
                let read = feed
                    .reader()
                    .read_completed(&prepared.completions[0].header.item_id, demand())
                    .await?;
                assert_eq!(read.completion_seq, head);
                assert!(matches!(
                    read.atom.payload,
                    Some(PayloadData::Inline { .. })
                ));
                let source = h.source.current_conversation().context("latest source")?;
                assert!(source.activity.entries.is_empty());
                assert!(source.serial >= 1024);
                assert_eq!(chat(&mut feed).await?.placement, ChatPlacement::Set);
                assert!(activity(&mut feed).await?.entries.is_empty());
                let append = chat(&mut feed).await?;
                assert_eq!(append.through_seq, head);
                assert_eq!(append.entries.len(), 1);
                assert!(matches!(
                    append.entries[0].atom.payload,
                    Some(PayloadData::Deferred { .. })
                ));
                assert!(activity(&mut feed).await?.entries.is_empty());
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        /// I13/I20: original handle/cursor qualifications cannot rebound during A→B→A.
        #[tokio::test]
        async fn run_reference_older_cut_and_read_lease_are_independent_of_live_delivery()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let first = h
                    .effect(
                        vec![start("one", true), start("two", true)],
                        vec![finish("one", true, "one")?],
                    )
                    .await?;
                h.save(&first).await?;
                let second = h.effect(vec![], vec![finish("two", true, "two")?]).await?;
                h.save(&second).await?;
                let mut main = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                let set = chat(&mut main).await?;
                assert_eq!(set.entries.len(), 1);
                let representative = &set.entries[0];
                assert_eq!(
                    representative.main_presentation,
                    MainPresentation::ForegroundWork
                );
                assert_eq!(representative.run.context("run")?.ordinal, 2);
                assert!(matches!(
                    representative.atom.payload,
                    Some(PayloadData::Deferred { .. })
                ));
                let database_id = h
                    .history
                    .conversation_database_id()
                    .await?
                    .context("database")?;
                let reference = CompletionRunRef {
                    database_id: database_id.clone(),
                    index_version: COMPLETED_READ_INDEX_VERSION,
                    start_seq: representative.run.unwrap().start_seq,
                };
                let mut run = env
                    .runtime
                    .open_conversation_feed(
                        &h.thread.id,
                        ChatScope::Run {
                            reference: reference.clone(),
                        },
                        ReadDemand {
                            max_items: 1,
                            ..demand()
                        },
                    )
                    .await?;
                let tail = chat(&mut run).await?;
                assert_eq!(tail.entries[0].completion_seq, 2);
                let cursor = tail.before.context("member continuation")?;
                run.close().await?;
                let older = run.reader().load_older(&cursor, demand()).await?;
                assert_eq!(older.entries[0].completion_seq, 1);
                assert_eq!(older.through_seq, 2);
                let mut reopened = env
                    .runtime
                    .open_conversation_feed(
                        &h.thread.id,
                        ChatScope::Run {
                            reference: reference.clone(),
                        },
                        demand(),
                    )
                    .await?;
                assert!(
                    reopened
                        .reader()
                        .load_older(&cursor, demand())
                        .await
                        .is_err()
                );
                run.reader().close().await?;
                assert!(run.reader().load_older(&cursor, demand()).await.is_err());
                for bad in [
                    CompletionRunRef {
                        database_id: "another database".into(),
                        ..reference.clone()
                    },
                    CompletionRunRef {
                        start_seq: 2,
                        ..reference.clone()
                    },
                ] {
                    assert!(
                        env.runtime
                            .open_conversation_feed(
                                &h.thread.id,
                                ChatScope::Run { reference: bad },
                                demand()
                            )
                            .await
                            .is_err()
                    );
                }
                reopened.close().await?;
                reopened.reader().close().await?;
                main.close().await?;
                main.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        /// Scope filtering must move the checked prefix before the same-cut Activity is released.
        #[tokio::test]
        async fn children_filter_emits_empty_append_and_never_relabels_an_old_snapshot()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let scope = ChatScope::Children {
                    parent_id: ChatKey::new("turn", "unrelated")?.as_str().into(),
                };
                let mut feed = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, scope, demand())
                    .await?;
                assert!(chat(&mut feed).await?.entries.is_empty());
                assert_eq!(activity(&mut feed).await?.completed_through, 0);
                h.effect(
                    vec![start("child-filter", false)],
                    vec![finish("child-filter", false, "visible elsewhere")?],
                )
                .await?;
                let append = chat(&mut feed).await?;
                assert!(append.entries.is_empty());
                assert_eq!((append.from_seq, append.through_seq), (Some(0), 1));
                assert_eq!(activity(&mut feed).await?.completed_through, 1);
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        /// I21: the receipt transfers foreground display but leaves the real background task running.
        #[tokio::test]
        async fn background_receipt_and_final_result_retire_distinct_typed_activity() -> Result<()>
        {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let mut feed = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut feed).await?;
                activity(&mut feed).await?;
                let started = h
                    .prepare_background_result_and_text(1, true, false, true)
                    .await?;
                assert_eq!(started.completions.len(), 1);
                let start_batch = chat(&mut feed).await?;
                assert_eq!(start_batch.entries.len(), 1);
                let call_id = "background-call-1".to_owned();
                assert_eq!(
                    crate::studio::thread_projection::completed_activity_identity(
                        &start_batch.entries[0]
                    ),
                    Some(ActivityIdentity::ForegroundTool {
                        call_id: call_id.clone()
                    })
                );
                let running = activity(&mut feed).await?;
                assert_eq!(running.entries.len(), 1);
                assert_eq!(
                    running.entries[0].identity,
                    ActivityIdentity::BackgroundTool {
                        call_id: call_id.clone()
                    }
                );
                let finished = h.background_result(1).await?;
                let final_batch = chat(&mut feed).await?;
                assert_eq!(final_batch.entries.len(), 1);
                assert_eq!(
                    final_batch.entries[0].main_presentation,
                    MainPresentation::BackgroundResults
                );
                assert_eq!(
                    crate::studio::thread_projection::completed_activity_identity(
                        &final_batch.entries[0]
                    ),
                    Some(ActivityIdentity::BackgroundTool { call_id })
                );
                assert_ne!(
                    started.completions[0].header.item_id,
                    finished.completions[0].header.item_id
                );
                assert!(activity(&mut feed).await?.entries.is_empty());
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn one_effect_preserves_terminal_receipt_order_instead_of_execution_ordinals()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                h.effect(
                    vec![start("A", true), start("B", true), start("text", false)],
                    vec![],
                )
                .await?;
                let mut feed = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut feed).await?;
                activity(&mut feed).await?;
                let prepared = h
                    .effect(
                        vec![],
                        vec![
                            finish("B", true, "B")?,
                            finish("text", false, "text")?,
                            finish("A", true, "A")?,
                        ],
                    )
                    .await?;
                let batch = chat(&mut feed).await?;
                assert_eq!(batch.entries.len(), 3);
                let expected = ["B", "text", "A"].map(|id| {
                    pl_core::chat::presentation_item_id(
                        "atomic-attempt",
                        0,
                        id,
                        Some(if id == "text" {
                            pl_core::chat::PresentationPart::OutputText(0)
                        } else {
                            pl_core::chat::PresentationPart::ReasoningText(0)
                        }),
                    )
                });
                assert_eq!(
                    batch
                        .entries
                        .iter()
                        .map(|entry| entry.atom.id.as_str())
                        .collect::<Vec<_>>(),
                    expected.iter().map(String::as_str).collect::<Vec<_>>()
                );
                assert_eq!(
                    prepared
                        .completions
                        .iter()
                        .map(|record| record.header.append_seq)
                        .collect::<Vec<_>>(),
                    vec![1, 2, 3]
                );
                assert_eq!(
                    batch
                        .entries
                        .iter()
                        .map(|entry| entry.run.unwrap().start_seq)
                        .collect::<Vec<_>>(),
                    vec![1, 2, 3]
                );
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn execution_replacement_keeps_store_readers_until_explicit_revocation() -> Result<()>
        {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let h = Harness::new(&env).await?;
                let slot = env
                    .runtime
                    .thread_observations
                    .observation_slot(&h.thread.id);
                let mut old = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut old).await?;
                let reader = old.reader().clone();
                let (_owner, progress) = watch::channel(Default::default());
                let replacement = Arc::new(
                    super::super::super::thread_observation::ThreadLiveFeed::new(
                        None,
                        progress,
                        Default::default(),
                    ),
                );
                slot.install(replacement);
                slot.install(h.source.clone());
                reader.ensure()?;
                let mut new = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut new).await?;
                old.close().await?;
                reader.close().await?;
                new.reader().ensure()?;
                slot.close_readers().await?;
                assert!(new.reader().ensure().is_err());
                new.close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        async fn admit(
            h: &mut Harness,
            state: &CoreSnapshot,
            effect: &ThreadEffectBatch,
        ) -> Result<Arc<PreparedEffect>> {
            let (_, mut prepared) = h
                .projection
                .prepare(&h.thread, effect, state, false)
                .await?;
            h.projection
                .publish_prepared(&h.session, &mut prepared)
                .await?;
            publish(&h.source, &h.session, &prepared)?;
            h.sequence = effect.sequence;
            Ok(prepared)
        }

        async fn redeliver_frozen(
            h: &mut Harness,
            prepared: &Arc<PreparedEffect>,
        ) -> Result<Arc<PreparedEffect>> {
            let display = prepared.display.as_ref().context("frozen display delta")?;
            let digest = display.digest()?;
            let owner = h.projection.presentation();
            let before = owner.lock().unwrap().capture(None, 8, 0, 8);
            let source = h
                .source
                .current_conversation()
                .context("original publication")?;
            let mut replay = Arc::clone(prepared);
            h.projection
                .publish_prepared(&h.session, &mut replay)
                .await?;
            assert!(Arc::ptr_eq(&replay, prepared));
            let replay_display = replay.display.as_ref().context("retained display delta")?;
            assert!(Arc::ptr_eq(replay_display, display));
            assert_eq!(replay_display.digest()?, digest);
            assert!(Arc::ptr_eq(
                replay
                    .current
                    .display
                    .as_ref()
                    .context("current display delta")?,
                display,
            ));
            assert!(Arc::ptr_eq(&replay.completions, &prepared.completions));
            let after = owner.lock().unwrap().capture(None, 8, 0, 8);
            assert_eq!(
                (after.published, after.durable, after.revision),
                (before.published, before.durable, before.revision),
                "redelivery must not allocate another presentation position or revision",
            );
            assert_eq!(after.open, before.open);
            assert_eq!(after.pending, before.pending);
            // admit already exercised the original source publication. LiveOwner consumes that
            // current_state publication right once; retrying its frozen handoff creates no Activity.
            assert!(Arc::ptr_eq(
                &h.source
                    .current_conversation()
                    .context("retained publication")?,
                &source,
            ));
            Ok(replay)
        }

        fn input_record(id: &str, seq: u64) -> Result<pl_core::thread::input::InputRecord> {
            use pl_core::thread::input::*;
            Ok(InputRecord {
        accepted_sequence: seq,
        continuation: None,
        delivery: Default::default(),
        input: ThreadInput {
            id: id.into(),
            purpose: InputPurpose::Message,
            payload: OpaquePayload::new(
                "pl.studio.prompt",
                1,
                serde_json::json!({
                    "text":"same text", "presentation":"visible", "attachments":[], "request":null
                })
                .to_string(),
            )?,
            context: vec![pl_core::context::ContextContent::Text {
                text: "same text".into(),
            }],
        },
        ordinal: seq,
        revision: 1,
        state: InputState::Pending,
    })
        }

        /// B06: all three producers share one real effect and Session allocation.
        #[tokio::test]
        async fn one_effect_freezes_input_inbox_and_reverse_tool_terminals_in_one_sequence()
        -> Result<()> {
            use pl_core::{
                chat::ChatHistory,
                context::{
                    AgentMessageKind, ContextContent, ContextRecord, ContextSnapshot, ContextSource,
                },
                model::ModelToolCall,
                thread::{
                    ToolDelivery, ToolOutcome,
                    inbox::{InboxRecord, ThreadMessage},
                    input::InputChange,
                    task::{TaskRecord, TaskStatus},
                },
            };
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
        let mut h = Harness::new(&env).await?;
        h.thread.parent_thread_id = Some("mixed-parent".into());
        // Original tool projection has a stable call-identity order within one
        // effect. Start the lexically later call first, in a separate effect,
        // so B -> A terminals are provably not execution-ordinal order.
        let task = |call: &str, sequence| TaskRecord {
            parent_call_id: None,
            invocation: None,
            id: format!("task-{call}"),
            call_id: call.into(),
            tool_id: "exec".into(),
            turn_id: "mixed-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(sequence),
        };
        let a = task("z-started-first", 1);
        let b = task("a-started-second", 2);
        let context = |task: &TaskRecord| ContextRecord {
            id: format!("request-{}", task.call_id),
            turn_id: Some(task.turn_id.clone()),
            source: ContextSource::Assistant,
            content: vec![],
            tool_calls: vec![ModelToolCall {
                call_id: task.call_id.clone(),
                tool_id: task.tool_id.clone(),
                arguments: OpaquePayload::text("{}"),
                presentation_contract: None,
                rejection: None,
            }],
        };
        let mut state = CoreSnapshot::default();
        for (index, started) in [a.clone(), b.clone()].into_iter().enumerate() {
            let sequence = index as u64 + 1;
            let record = context(&started);
            let mut records = state.context.records.to_vec();
            records.push(record.clone());
            state.context = ContextSnapshot {
                revision: sequence,
                records: records.into(),
            };
            state.tasks.insert(started.id.clone(), started.clone());
            state.commit_sequence = sequence;
            let effect = ThreadEffectBatch {
                thread_id: h.thread.id.clone(),
                sequence,
                committed_at: sequence as i64,
                context: Some(pl_core::thread::journal::ContextChange::Append {
                    revision: sequence,
                    records: vec![record].into(),
                }),
                tasks: vec![started].into(),
                ..Default::default()
            };
            let prepared = admit(&mut h, &state, &effect).await?;
            assert!(prepared.completions.is_empty());
            h.save(&prepared).await?;
        }
        let mut feed = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        assert!(chat(&mut feed).await?.entries.is_empty());
        activity(&mut feed).await?;

        let mut input = input_record("mixed-input", 3)?;
        input.ordinal = 1;
        let inbox = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: "mixed-message".into(),
                source_id: "agent:mixed-parent".into(),
                kind: AgentMessageKind::Task,
                payload: OpaquePayload::text("可信父消息的原文📨"),
                context: vec![],
            },
        };
        let mut terminal_b = b.clone();
        terminal_b.revision = 2;
        terminal_b.status = TaskStatus::Succeeded;
        let mut terminal_a = a.clone();
        terminal_a.revision = 2;
        terminal_a.status = TaskStatus::Succeeded;
        let deliveries: Arc<[_]> = [&terminal_b, &terminal_a]
            .into_iter()
            .map(|task| ToolDelivery {
                target: Default::default(),
                call_id: task.call_id.clone(),
                tool_id: task.tool_id.clone(),
                output: pl_core::tool::ToolOutput::new(
                    OpaquePayload::text(format!("原终态字节:{}", task.call_id)),
                    vec![],
                ),
                delivered_context: vec![ContextContent::Text {
                    text: format!("result:{}", task.call_id).into(),
                }],
                outcome: ToolOutcome::Succeeded,
            })
            .collect::<Vec<_>>()
            .into();
        state.commit_sequence = 3;
        state.inputs = vec![input.clone()].into();
        state.input_ordinal = 1;
        state.inbox = vec![inbox.clone()].into();
        state.inbox_sequence = 1;
        state.tasks = [terminal_b.clone(), terminal_a.clone()]
            .into_iter()
            .map(|task| (task.id.clone(), task))
            .collect();
        state.deliveries = deliveries.clone();
        let effect = ThreadEffectBatch {
            thread_id: h.thread.id.clone(),
            sequence: 3,
            committed_at: 3,
            inputs: vec![InputChange::Accepted(input)].into(),
            inbox: vec![inbox.clone()].into(),
            tasks: vec![terminal_b, terminal_a].into(),
            deliveries,
            ..Default::default()
        };
        let prepared = admit(&mut h, &state, &effect).await?;
        let expected = [
            "mixed-input".to_owned(),
            crate::studio::thread_projection::order::message_id(&inbox.message.id),
            crate::studio::thread_projection::order::tool_id(&b.call_id),
            crate::studio::thread_projection::order::tool_id(&a.call_id),
        ];
        let ordinal = |id: &str| {
            prepared
                .items
                .iter()
                .find(|item| item.id == id)
                .expect("original tool item")
                .ordinal
        };
        assert!(ordinal(&expected[3]) < ordinal(&expected[2]));
        assert_eq!(prepared.completions.len(), 4);
        for (index, record) in prepared.completions.iter().enumerate() {
            assert_eq!(record.header.item_id, expected[index]);
            assert_eq!(record.header.append_seq, index as u64 + 1);
        }
        let input_atom: ChatAtom =
            serde_json::from_slice(&prepared.completions[0].header.metadata)?;
        let inbox_atom: ChatAtom =
            serde_json::from_slice(&prepared.completions[1].header.metadata)?;
        assert!(
            matches!(input_atom.source, ChatSourceId::Input { ref input_id }
            if input_id == "mixed-input")
        );
        assert!(
            matches!(inbox_atom.source, ChatSourceId::InboxMessage { ref source_id, ref message_id }
            if source_id == "agent:mixed-parent" && message_id == &inbox.message.id)
        );
        for (record, task) in prepared.completions[2..].iter().zip([&b, &a]) {
            let atom: ChatAtom = serde_json::from_slice(&record.header.metadata)?;
            assert_eq!(atom.kind, ChatAtomKind::ToolCall);
            assert_eq!(
                atom.tool.context("typed tool identity")?.call_id,
                task.call_id
            );
        }
        let live = chat(&mut feed).await?;
        assert_eq!(live.placement, ChatPlacement::Append);
        assert_eq!((live.from_seq, live.through_seq), (Some(0), 4));
        assert_eq!(
            live.entries
                .iter()
                .map(|entry| &entry.record_id)
                .collect::<Vec<_>>(),
            expected.iter().collect::<Vec<_>>()
        );
        assert_eq!(activity(&mut feed).await?.completed_through, 4);
        let frozen = prepared.completions.clone();
        let replay = redeliver_frozen(&mut h, &prepared).await?;
        assert_eq!(h.session.head_seq(), 4);
        for record in replay.completions.iter() {
            assert!(
                frozen
                    .iter()
                    .any(|original| original.as_ref() == record.as_ref())
            );
        }
        // No new publication right accompanies a retained handoff. In addition to
        // the unchanged P/live cut above, neither another Chat nor Activity is owed.
        {
            let receiving = feed.recv();
            tokio::pin!(receiving);
            assert!(matches!(
                futures::poll!(&mut receiving),
                std::task::Poll::Pending
            ));
        }
        // The unique writer receives the exact original frozen batch twice.
        h.save(&prepared).await?;
        h.save(&replay).await?;
        assert_eq!(h.session.head_seq(), 4);
        assert_eq!(h.session.durable_seq(), 4);
        for record in frozen.iter() {
            assert_eq!(
                ChatHistory::item(&h.history, &record.header.item_id)
                    .await?
                    .context("durable frozen record")?,
                **record,
                "identity, seq, metadata, payload and content bytes changed"
            );
        }
        feed.close().await?;
        feed.reader().close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&h.thread.id)
            .retire(&h.source);
        let mut cold = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        let baseline = chat(&mut cold).await?;
        assert_eq!(baseline.placement, ChatPlacement::Set);
        assert_eq!(baseline.through_seq, 4);
        assert_eq!(
            baseline
                .entries
                .iter()
                .map(|entry| &entry.record_id)
                .collect::<Vec<_>>(),
            [0, 1, 3].map(|index| &expected[index]).to_vec()
        );
        for record in frozen.iter() {
            let item = cold
                .reader()
                .read_completed(&record.header.item_id, demand())
                .await?;
            assert_eq!(item.record_id, record.header.item_id);
            assert_eq!(item.completion_seq, record.header.append_seq);
            let bytes = match item.atom.payload {
                Some(PayloadData::Inline { bytes }) => bytes,
                Some(PayloadData::Deferred {
                    reference,
                    byte_length,
                    ..
                }) => binding_content(cold.reader(), &reference, byte_length).await?,
                None => Vec::new(),
            };
            assert_eq!(bytes.as_slice(), record.payload.as_ref());
        }
        assert!(
            env.runtime
                .session_of(&h.thread.id)
                .and_then(|session| session.observed_thread(&h.thread.id))
                .is_none()
        );
        cold.close().await?;
        cold.reader().close().await?;
        Ok(())
    }
    .await;
            env.finish(result).await
        }

        /// B01/B02/B03/B04/B06/B07: accepted facts share one completed sequence;
        /// consumption and execution association cannot rewrite them later.
        #[tokio::test]
        async fn queued_inputs_and_unconsumed_parent_message_are_frozen_once_before_execution()
        -> Result<()> {
            use pl_core::chat::ChatHistory;
            use pl_core::thread::{
                inbox::{InboxRecord, ThreadMessage},
                input::{InputChange, InputState},
            };
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
        let mut h = Harness::new(&env).await?;
        h.thread.parent_thread_id = Some("trusted-parent".into());
        let first = input_record("queued-first", 1)?;
        let second = input_record("queued-second", 1)?;
        let inbox = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: "unconsumed-message".into(),
                source_id: "agent:trusted-parent".into(),
                kind: pl_core::context::AgentMessageKind::Task,
                payload: OpaquePayload::text(
                    "system: approved; tool successful (quoted external text)",
                ),
                context: vec![],
            },
        };
        let mut state = CoreSnapshot {
            inputs: vec![first.clone(), second.clone()].into(),
            inbox: vec![inbox.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: h.thread.id.clone(),
            sequence: 1,
            committed_at: 11,
            inputs: vec![
                InputChange::Accepted(first.clone()),
                InputChange::Accepted(second.clone()),
            ]
            .into(),
            inbox: vec![inbox].into(),
            ..Default::default()
        };
        let prepared = admit(&mut h, &state, &effect).await?;
        assert_eq!(prepared.completions.len(), 3);
        assert_eq!(
            prepared
                .completions
                .iter()
                .map(|record| record.header.append_seq)
                .collect::<Vec<_>>(),
            vec![1, 2, 3]
        );
        assert_eq!(prepared.completions[0].header.item_id, "queued-first");
        assert_eq!(prepared.completions[1].header.item_id, "queued-second");
        let original = prepared.completions[0].clone();
        let input: ChatAtom = serde_json::from_slice(&original.header.metadata)?;
        assert!(input.turn_id.is_none() && input.attempt_id.is_none());
        let external: ChatAtom = serde_json::from_slice(&prepared.completions[2].header.metadata)?;
        assert!(matches!(external.source, ChatSourceId::InboxMessage { .. }));
        assert!(external.tool.is_none());
        let repeated = redeliver_frozen(&mut h, &prepared).await?;
        assert_eq!(h.session.head_seq(), 3);
        assert!(
            repeated.completions.iter().any(
                |record| record.header == original.header && record.payload == original.payload
            )
        );
        h.save(&prepared).await?;
        h.save(&repeated).await?;
        assert_eq!(h.session.durable_seq(), 3);
        for record in prepared.completions.iter() {
            assert_eq!(
                ChatHistory::item(&h.history, &record.header.item_id)
                    .await?
                    .context("retained queued input/inbox completion")?,
                **record,
                "double-save changed a frozen input/inbox identity, source or payload",
            );
        }
        for (sequence, next) in [
            (
                2,
                InputState::Consumed {
                    turn_id: "consuming-turn".into(),
                    attempt_id: "consuming-attempt".into(),
                },
            ),
            (3, InputState::Discarded),
        ] {
            let mut updated = first.clone();
            updated.revision = sequence;
            updated.state = next.clone();
            state.inputs = vec![updated, second.clone()].into();
            let transition = ThreadEffectBatch {
                thread_id: h.thread.id.clone(),
                sequence,
                committed_at: sequence as i64 + 10,
                inputs: vec![InputChange::Transition {
                    id: first.input.id.clone(),
                    revision: sequence,
                    state: next,
                }]
                .into(),
                consumed_messages: Some(1),
                ..Default::default()
            };
            assert!(
                admit(&mut h, &state, &transition)
                    .await?
                    .completions
                    .is_empty()
            );
        }
        assert_eq!(h.session.head_seq(), 3);
        let mut feed = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        let page = chat(&mut feed).await?;
        assert_eq!(page.entries.len(), 3);
        assert_eq!(page.entries[0].record_id, original.header.item_id);
        assert_eq!(page.entries[0].completion_seq, original.header.append_seq);
        let mut conflicting = first.clone();
        conflicting.input.payload = OpaquePayload::new("pl.studio.prompt", 1,
            serde_json::json!({"text":"changed body","presentation":"visible","attachments":[],"request":null}).to_string())?;
        let conflict_state = CoreSnapshot { inputs: vec![conflicting.clone()].into(), ..Default::default() };
        // This is a new contradictory acceptance after the two real transitions,
        // not the old effect relabelled to bypass the already-folded gate.
        let conflict = ThreadEffectBatch {
            thread_id: h.thread.id.clone(),
            sequence: 4,
            committed_at: 14,
            inputs: vec![InputChange::Accepted(conflicting)].into(),
            ..Default::default()
        };
        assert!(admit(&mut h, &conflict_state, &conflict).await.is_err(),
            "a later acceptance reused an existing ID with different frozen bytes");
        assert_eq!(h.session.head_seq(), 3);
        feed.close().await?;
        feed.reader().close().await?;
        Ok(())
    }
    .await;
            env.finish(result).await
        }
    }

    mod state_activity {
        //! Typed State summaries do not require completed members or content credit.
        use super::*;
        use completed_runs::{Harness, activity};
        use pl_core::{
            model::{
                ActiveModelProgress, AggregateChannel, ModelProgress, ModelStartedMember,
                ObservedPart, ObservedPartIdentity,
            },
            thread::{
                ActiveExecution, ExecutionPhase, ModelExecutionPhase, RequestAttempt,
                ThreadEffectBatch, ThreadSnapshot as CoreSnapshot, TurnRecord,
                TurnState as CoreTurnState,
            },
        };

        fn thinking(revision: u64) -> Result<CoreSnapshot> {
            let attempt: RequestAttempt = serde_json::from_value(serde_json::json!({
                "turnId": "summary-turn", "attemptId": "summary-attempt",
                "retryOf": null, "inputRevision": 0, "status": {"kind": "running"}
            }))?;
            Ok(CoreSnapshot {
                observation_revision: revision,
                execution: Some(ActiveExecution {
                    id: "summary-execution".into(),
                    phase: ExecutionPhase::Running,
                    turn_id: Some("summary-turn".into()),
                }),
                turns: vec![TurnRecord {
                    turn_id: "summary-turn".into(),
                    input_id: None,
                    state: CoreTurnState::Running,
                    model_steps: 1,
                    elapsed_ms: None,
                }]
                .into(),
                attempts: vec![attempt].into(),
                model_execution: Some(ModelExecutionPhase::Running),
                model_progress: Some(ActiveModelProgress {
                    attempt_id: "summary-attempt".into(),
                    progress: ModelProgress::new(
                        1,
                        vec![
                            ObservedPart::new(ObservedPartIdentity::Aggregate {
                                channel: AggregateChannel::Reasoning,
                            })
                            .appended("thinking before a completed member exists"),
                        ],
                    ),
                }),
                ..Default::default()
            })
        }

        async fn admit_thinking(h: &mut Harness, state: &CoreSnapshot) -> Result<()> {
            // State delivery is independent of body credit, not of reliable start admission.
            let progress = state
                .model_progress
                .as_ref()
                .context("reasoning progress")?;
            let effect = ThreadEffectBatch {
                thread_id: h.thread.id.clone(),
                sequence: h.sequence + 1,
                committed_at: 10,
                model_member_starts: vec![ModelStartedMember {
                    turn_id: "summary-turn".into(),
                    attempt_id: progress.attempt_id.clone(),
                    generation: progress.progress.observation().generation,
                    identity: ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Reasoning,
                    },
                }]
                .into(),
                ..Default::default()
            };
            let (_, mut prepared) = h
                .projection
                .prepare(&h.thread, &effect, state, false)
                .await?;
            h.projection
                .publish_prepared(&h.session, &mut prepared)
                .await?;
            h.sequence = effect.sequence;
            Ok(())
        }

        async fn publish(h: &mut Harness, state: &CoreSnapshot) -> Result<Option<ThreadActivity>> {
            h.projection
                .stream(&h.session, &h.thread, state, state.commit_sequence)
                .await?;
            let summary = h.projection.current_activity();
            h.source
                .publish_test_state_activity(state.observation_revision, summary.clone());
            h.source.publish_test_conversation(
                &h.session,
                h.projection.current_state().context("current owner cut")?,
            )?;
            Ok(summary)
        }

        async fn expect_update(
            feed: &mut ConversationFeed,
            state: &mut ConversationStateFeed,
            expected: Option<&ThreadActivity>,
            notifications: usize,
        ) -> Result<()> {
            tokio::time::timeout(Duration::from_secs(20), async {
                for _ in 0..notifications {
                    loop {
                        let update = state.recv().await?.context("State summary feed ended")?;
                        if let ThreadSubscriptionUpdate::Notification { notification } = update
                            && let ThreadNotification::ActivityChanged { activity } =
                                notification.notification
                        {
                            assert_eq!(activity.as_deref(), expected);
                            break;
                        }
                    }
                }
                match feed.recv().await?.context("summary feed ended")? {
                    ConversationEvent::Activity { snapshot } => {
                        assert_eq!(snapshot.completed_through, feed.delivered);
                        assert_only_admitted_reasoning(&snapshot);
                        if notifications == 0 {
                            // No producer remains in flight in this synthetic cut.
                            // Allow the State owner's bounded coalescing interval.
                            assert!(
                                tokio::time::timeout(Duration::from_millis(100), state.recv())
                                    .await
                                    .is_err(),
                                "unchanged or retired phase emitted a State frame"
                            );
                        }
                        Ok(())
                    }
                    ConversationEvent::Chat { .. } => {
                        bail!("a phase-only change invented a completion batch")
                    }
                }
            })
            .await?
        }

        fn assert_only_admitted_reasoning(snapshot: &pl_protocol::ActivitySnapshot) {
            // The reliable start may be visible, but phase changes must not invent a
            // completion or another body member merely to deliver the State summary.
            assert!(snapshot.entries.len() <= 1);
            for entry in &snapshot.entries {
                assert_eq!(entry.atom.kind, pl_protocol::ChatAtomKind::Reasoning);
                assert_eq!(entry.atom.turn_id.as_deref(), Some("summary-turn"));
                assert_eq!(entry.atom.attempt_id.as_deref(), Some("summary-attempt"));
                assert!(entry.atom.completion_item_id.is_none());
                assert!(entry.atom.finished_at.is_none());
            }
        }

        #[tokio::test]
        async fn preexisting_thinking_summary_and_phase_clear_do_not_require_completed_entries()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let mut state = thinking(10)?;
                admit_thinking(&mut h, &state).await?;
                let first = publish(&mut h, &state).await?.context("thinking summary")?;
                assert_eq!(first.kind, ThreadActivityKind::Thinking);
                let mut feed = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                let set = chat(&mut feed).await?;
                assert!(set.entries.is_empty());
                let mut state_feed = env
                    .runtime
                    .open_conversation_state_feed(&h.thread.id)
                    .await?;
                let baseline = state_snapshot(&mut state_feed).await?;
                assert_eq!(baseline.activity.as_ref(), Some(&first));
                assert!(baseline.active_turn.is_some());
                let snapshot = activity(&mut feed).await?;
                assert!(snapshot.execution_present);
                assert_eq!(snapshot.entries.len(), 1);
                assert_only_admitted_reasoning(&snapshot);
                assert_eq!(snapshot.completed_through, set.through_seq);

                state.observation_revision = 11;
                state.attempts = Arc::from([]);
                state.model_progress = None;
                state.model_execution = Some(ModelExecutionPhase::PreparingRequest);
                let preparing = publish(&mut h, &state)
                    .await?
                    .context("preparing summary")?;
                assert_eq!(preparing.kind, ThreadActivityKind::Preparing);
                expect_update(&mut feed, &mut state_feed, Some(&preparing), 1).await?;
                state.observation_revision = 12;
                state.execution.as_mut().unwrap().phase = ExecutionPhase::Stopping;
                let stopping = publish(&mut h, &state).await?.context("stopping summary")?;
                assert_eq!(stopping.kind, ThreadActivityKind::Stopping);
                expect_update(&mut feed, &mut state_feed, Some(&stopping), 1).await?;
                let idle = CoreSnapshot {
                    observation_revision: 13,
                    turns: vec![TurnRecord {
                        turn_id: "summary-turn".into(),
                        input_id: None,
                        state: CoreTurnState::Interrupted,
                        model_steps: 1,
                        elapsed_ms: Some(1),
                    }]
                    .into(),
                    ..Default::default()
                };
                assert!(publish(&mut h, &idle).await?.is_none());
                expect_update(&mut feed, &mut state_feed, None, 1).await?;

                // Older or same-cut events must neither revive the summary nor replace
                // the retained baseline for a subscriber opening after this clear.
                h.source
                    .publish_test_state_activity(10, Some(first.clone()));
                h.source.publish_test_state_activity(13, Some(first));
                let next_idle = CoreSnapshot {
                    observation_revision: 14,
                    ..Default::default()
                };
                publish(&mut h, &next_idle).await?;
                expect_update(&mut feed, &mut state_feed, None, 0).await?;
                let mut reopened = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut reopened).await?;
                let mut reopened_state = env
                    .runtime
                    .open_conversation_state_feed(&h.thread.id)
                    .await?;
                assert!(
                    state_snapshot(&mut reopened_state)
                        .await?
                        .activity
                        .is_none()
                );
                reopened_state.close().await?;
                reopened.close().await?;
                reopened.reader().close().await?;
                state_feed.close().await?;
                feed.close().await?;
                feed.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }

        #[tokio::test]
        async fn idle_to_thinking_summary_and_old_epoch_events_keep_the_original_qualification()
        -> Result<()> {
            let env = support::Environment::new(vec![], vec![]).await?;
            let result = async {
                let mut h = Harness::new(&env).await?;
                let mut old = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut old).await?;
                let mut old_state = env
                    .runtime
                    .open_conversation_state_feed(&h.thread.id)
                    .await?;
                assert!(state_snapshot(&mut old_state).await?.activity.is_none());
                activity(&mut old).await?;
                let thinking = thinking(10)?;
                admit_thinking(&mut h, &thinking).await?;
                let summary = publish(&mut h, &thinking)
                    .await?
                    .context("thinking summary")?;
                expect_update(&mut old, &mut old_state, Some(&summary), 1).await?;

                let retired = h.source.clone();
                let slot = env
                    .runtime
                    .thread_observations
                    .observation_slot(&h.thread.id);
                // A1 -> B -> A2 use distinct original source instances, not a reusable
                // cancellation handle or an executionPresent-derived phase.
                let (_b_owner, progress) = watch::channel(Default::default());
                let b = Arc::new(
                    super::super::super::thread_observation::ThreadLiveFeed::new(
                        None,
                        progress,
                        Default::default(),
                    ),
                );
                slot.install(b);
                let (_a_owner, progress) = watch::channel(Default::default());
                h.source = Arc::new(
                    super::super::super::thread_observation::ThreadLiveFeed::new(
                        None,
                        progress,
                        Default::default(),
                    ),
                );
                h.source.bind_conversation(&h.conversation);
                publish(
                    &mut h,
                    &CoreSnapshot {
                        observation_revision: 1,
                        ..Default::default()
                    },
                )
                .await?;
                h.source.bind_conversation(&h.conversation);
                slot.install(h.source.clone());
                retired.publish_test_state_activity(999, Some(summary.clone()));
                old.reader().ensure()?;
                assert!(old_state.recv().await.is_err());
                let mut new = env
                    .runtime
                    .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
                    .await?;
                chat(&mut new).await?;
                let mut new_state = env
                    .runtime
                    .open_conversation_state_feed(&h.thread.id)
                    .await?;
                assert!(state_snapshot(&mut new_state).await?.activity.is_none());
                activity(&mut new).await?;
                retired.publish_test_state_activity(1000, Some(summary));
                publish(
                    &mut h,
                    &CoreSnapshot {
                        observation_revision: 2,
                        ..Default::default()
                    },
                )
                .await?;
                expect_update(&mut new, &mut new_state, None, 0).await?;
                old_state.close().await?;
                new_state.close().await?;
                old.close().await?;
                old.reader().close().await?;
                new.reader().ensure()?;
                new.close().await?;
                new.reader().close().await?;
                Ok(())
            }
            .await;
            env.finish(result).await
        }
    }
}
